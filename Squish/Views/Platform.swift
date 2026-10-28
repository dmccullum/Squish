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
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Squish should save images"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Prompt for images and/or folders to squish.
    static func chooseInputs() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Add"
        panel.message = "Choose images or a folder to squish"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
