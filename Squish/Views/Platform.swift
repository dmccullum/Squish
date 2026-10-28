import AppKit
import DMKit
import UniformTypeIdentifiers

/// Thin AppKit helpers for things SwiftUI doesn't cover natively on macOS.
enum Platform {
    /// Reveal & select the given files in Finder.
    static func reveal(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    /// The window a menu-bar command's panel attaches to: the key window (the
    /// main window or Settings), or the main window while a panel such as
    /// Quick Look is key.
    static var commandWindow: NSWindow? {
        if let key = NSApp.keyWindow, !(key is NSPanel) { return key }
        return NSApp.mainWindow
    }

    /// Prompt for an output folder, as a sheet on `window`.
    static func chooseFolder(in window: NSWindow?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Squish should save images"
        return await panel.present(in: window) == .OK ? panel.url : nil
    }

    /// Prompt for images and/or folders to squish, as a sheet on `window`.
    static func chooseInputs(in window: NSWindow?) async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Squish"
        panel.message = "Choose images or a folder to squish"
        return await panel.present(in: window) == .OK ? panel.urls : []
    }
}
