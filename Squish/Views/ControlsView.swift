import SwiftUI

struct ControlsView: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SizeTile()
            DimensionTile()
            FormatTile()
        }
        .animation(.snappy(duration: 0.2), value: settings.sizeTargetEnabled)
        .animation(.snappy(duration: 0.2), value: settings.dimensionEnabled)
        .animation(.snappy(duration: 0.2), value: settings.formatEnabled)
    }
}

// MARK: - Tile shell

private struct TileShell<Content: View>: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 2)
                Toggle("", isOn: $isOn.animation(.snappy(duration: 0.2)))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            content
                .frame(maxWidth: .infinity)
                .opacity(isOn ? 1 : 0.4)
                .disabled(!isOn)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
        )
    }
}

private struct ValueBadge: View {
    let value: String
    let caption: String
    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            Image(systemName: "slider.horizontal.3")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
    }
}

// MARK: - File size

private struct SizeTile: View {
    @EnvironmentObject private var settings: SquishSettings
    @State private var showPopover = false

    private var bytes: Binding<Double> {
        Binding(get: { Double(settings.targetBytes) },
                set: { newBytes in
                    if newBytes >= 1_000_000 {
                        settings.sizeUnit = .mb
                        settings.sizeValue = (newBytes / 1_000_000 * 10).rounded() / 10
                    } else {
                        settings.sizeUnit = .kb
                        settings.sizeValue = (newBytes / 1_000 / 10).rounded() * 10
                    }
                })
    }

    var body: some View {
        TileShell(icon: "scalemass", title: "File size", isOn: $settings.sizeTargetEnabled) {
            if settings.controlStyle == .dial {
                DialControl(value: bytes, range: 50_000...25_000_000, logScale: true,
                            enabled: settings.sizeTargetEnabled,
                            format: { ByteFormat.string(Int($0)) })
            } else {
                Button { showPopover = true } label: {
                    ValueBadge(value: valueText, caption: "target")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    SizePopover().environmentObject(settings).frame(width: 250)
                }
            }
        }
    }

    private var valueText: String {
        let v = settings.sizeValue
        let s = v.rounded() == v ? String(Int(v)) : String(v)
        return "\(s) \(settings.sizeUnit.rawValue)"
    }
}

private struct SizePopover: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target file size").font(.headline)
            HStack(spacing: 8) {
                TextField("Size", value: $settings.sizeValue, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                Picker("", selection: $settings.sizeUnit) {
                    ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
            }
            if !settings.sizePresets.isEmpty {
                Text("Presets").font(.caption).foregroundStyle(.secondary)
                ChipGrid(settings.sizePresets.map { ($0.id, $0.name, $0.valueLabel) }) { id in
                    if let p = settings.sizePresets.first(where: { $0.id == id }) {
                        settings.sizeValue = p.value; settings.sizeUnit = p.unit
                    }
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Dimensions

private struct DimensionTile: View {
    @EnvironmentObject private var settings: SquishSettings
    @State private var showPopover = false

    private var longSide: Binding<Double> {
        Binding(get: { Double(settings.longSide) },
                set: { settings.longSide = Int($0); settings.dimensionMode = .maxLongSide })
    }

    var body: some View {
        TileShell(icon: "arrow.up.left.and.arrow.down.right", title: "Dimensions", isOn: $settings.dimensionEnabled) {
            if settings.controlStyle == .dial {
                DialControl(value: longSide, range: 256...8192, step: 16,
                            enabled: settings.dimensionEnabled,
                            format: { "\(Int($0))px" })
            } else {
                Button { showPopover = true } label: {
                    ValueBadge(value: valueText, caption: settings.dimensionMode.shortName.lowercased())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    DimensionPopover().environmentObject(settings).frame(width: 260)
                }
            }
        }
    }

    private var valueText: String {
        switch settings.dimensionMode {
        case .maxLongSide: return "\(settings.longSide)"
        case .maxWidth:    return "\(settings.maxWidth)"
        case .maxHeight:   return "\(settings.maxHeight)"
        case .fit:         return "\(settings.fitWidth)×\(settings.fitHeight)"
        }
    }
}

private struct DimensionPopover: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maximum size").font(.headline)
            Picker("", selection: $settings.dimensionMode) {
                ForEach(DimensionMode.allCases) { Text($0.displayName).tag($0) }
            }.labelsHidden()

            switch settings.dimensionMode {
            case .maxLongSide: pixelField("Longest side", $settings.longSide)
            case .maxWidth:    pixelField("Width", $settings.maxWidth)
            case .maxHeight:   pixelField("Height", $settings.maxHeight)
            case .fit:
                HStack(spacing: 8) {
                    pixelField("W", $settings.fitWidth)
                    Text("×").foregroundStyle(.secondary)
                    pixelField("H", $settings.fitHeight)
                }
            }

            if !settings.dimensionPresets.isEmpty {
                Text("Presets").font(.caption).foregroundStyle(.secondary)
                ChipGrid(settings.dimensionPresets.map { ($0.id, $0.name, "\($0.pixels)") }) { id in
                    if let p = settings.dimensionPresets.first(where: { $0.id == id }) {
                        settings.dimensionMode = .maxLongSide
                        settings.longSide = p.pixels
                    }
                }
            }
        }
        .padding(14)
    }

    private func pixelField(_ label: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70)
            Text("px").font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Format

private struct FormatTile: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        TileShell(icon: "photo", title: "Format", isOn: $settings.formatEnabled) {
            VStack(spacing: 8) {
                ForEach(OutputFormat.allCases) { fmt in
                    Button { settings.format = fmt } label: {
                        Text(fmt.displayName)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(settings.format == fmt ? Color.accentColor : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(settings.format == fmt ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Chip grid

private struct ChipGrid: View {
    let items: [(id: UUID, name: String, value: String)]
    let action: (UUID) -> Void

    init(_ items: [(UUID, String, String)], action: @escaping (UUID) -> Void) {
        self.items = items.map { (id: $0.0, name: $0.1, value: $0.2) }
        self.action = action
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button { action(item.id) } label: {
                    HStack(spacing: 4) {
                        Text(item.name).fontWeight(.medium)
                        Text(item.value).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
