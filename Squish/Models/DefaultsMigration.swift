import Foundation

/// Squish shipped as `com.squish.app` before 2026-10. On the first launch
/// under the current bundle identifier, copy the settings and presets saved
/// under the old one so nothing is lost. The old domain is left in place.
nonisolated enum DefaultsMigration {
    static let oldBundleID = "com.squish.app"
    static let markerKey = "migratedFromBundleID"

    static func run(defaults: UserDefaults = .standard, bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let bundleID, bundleID != oldBundleID,
              defaults.string(forKey: markerKey) == nil else { return }
        defer { defaults.set(oldBundleID, forKey: markerKey) }

        // Only copy into a domain that has none of the app's own keys yet.
        let current = defaults.persistentDomain(forName: bundleID) ?? [:]
        guard appKeys(current).isEmpty,
              let old = defaults.persistentDomain(forName: oldBundleID) else { return }
        for (key, value) in appKeys(old) {
            defaults.set(value, forKey: key)
        }
    }

    /// Drops AppKit and system keys (window frames, panel state) so only the
    /// app's own settings move.
    static func appKeys(_ domain: [String: Any]) -> [String: Any] {
        domain.filter { key, _ in
            !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple.") && key != markerKey
        }
    }
}
