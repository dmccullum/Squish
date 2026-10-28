import AppKit
import UniformTypeIdentifiers

/// Thin AppKit helpers for things SwiftUI doesn't cover natively on macOS.
enum Platform {
    /// Reveal & select the given files in Finder.
    static func reveal(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    /// Prompt for an output folder.
    static func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Squish should save images"
        return await panel.present() ? panel.url : nil
    }

    /// Prompt for images and/or folders to squish.
    static func chooseInputs() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Add"
        panel.message = "Choose images or a folder to squish"
        return await panel.present() ? panel.urls : []
    }
}

extension NSOpenPanel {
    /// Shows the panel as a sheet on the front window (the main window or
    /// Settings), or app-modal when no window is open. Returns whether the
    /// person confirmed.
    func present() async -> Bool {
        guard let window = [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }).first(where: { !($0 is NSPanel) }) else {
            return runModal() == .OK
        }
        guard window.attachedSheet == nil else { return false }
        return await beginSheetModal(for: window) == .OK
    }
}
