import SwiftUI

struct ControlsView: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SizeTile()
            DimensionTile()
        }
        .animation(.snappy(duration: 0.2), value: settings.sizeTargetEnabled)
        .animation(.snappy(duration: 0.2), value: settings.dimensionEnabled)
    }
}

// MARK: - Glass tile shell

private struct GlassTile<Content: View>: View {
    let icon: String
    let title: String
    /// nil → no switch; the control is always on (e.g. Format).
    var toggle: Binding<Bool>? = nil
    @ViewBuilder var content: Content

    private var on: Bool { toggle?.wrappedValue ?? true }
    /// Only tint the glass for toggleable controls that are switched on.
    private var tinted: Bool { toggle != nil && on }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 2)
                if let toggle {
                    Toggle("", isOn: toggle.animation(.snappy(duration: 0.2)))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
            }
            content
                .frame(maxWidth: .infinity)
                .opacity(on ? 1 : 0.4)
                .disabled(!on)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 162, maxHeight: 162)
        .glassCard(cornerRadius: 18, isOn: tinted)
    }
}

/// Subtle "tap for options" affordance shown under a dial.
private struct EditHint: View {
    var body: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(.ultraThinMaterial))
            .opacity(0.9)
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
        GlassTile(icon: "scalemass", title: "File size", toggle: $settings.sizeTargetEnabled) {
            ZStack(alignment: .bottom) {
                DialControl(value: bytes, range: 50_000...100_000_000, logScale: true,
                            enabled: settings.sizeTargetEnabled,
                            format: { ByteFormat.string(Int($0)) })
                EditHint().padding(.bottom, 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { showPopover = true }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                SizePopover().environmentObject(settings).frame(width: 250)
            }
        }
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
                ChipGrid(settings.sortedSizePresets.map { ($0.id, $0.name, $0.valueLabel) }) { id in
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
        GlassTile(icon: "arrow.up.left.and.arrow.down.right", title: "Dimensions", toggle: $settings.dimensionEnabled) {
            ZStack(alignment: .bottom) {
                if settings.dimensionMode == .maxLongSide {
                    DialControl(value: longSide, range: 256...8192, step: 16,
                                enabled: settings.dimensionEnabled,
                                format: { "\(Int($0))px" })
                } else {
                    // Advanced modes are number-based; show the value, edit in popover.
                    VStack(spacing: 2) {
                        Text(advancedValue)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text(settings.dimensionMode.shortName.lowercased())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                EditHint().padding(.bottom, 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { showPopover = true }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                DimensionPopover().environmentObject(settings).frame(width: 290)
            }
        }
    }

    private var advancedValue: String {
        switch settings.dimensionMode {
        case .maxWidth:  return "\(settings.maxWidth)"
        case .maxHeight: return "\(settings.maxHeight)"
        case .fit:       return "\(settings.fitWidth)×\(settings.fitHeight)"
        case .maxLongSide: return "\(settings.longSide)"
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
                ChipGrid(settings.sortedDimensionPresets.map { ($0.id, $0.name, "\($0.pixels)") }) { id in
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
            Text(label).font(.callout).foregroundStyle(.secondary).fixedSize()
            TextField(label, value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 64)
            Text("px").font(.callout).foregroundStyle(.secondary).fixedSize()
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
