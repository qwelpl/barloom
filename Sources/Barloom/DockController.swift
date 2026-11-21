import Foundation

/// macOS only keeps windows clear of the Dock, so Barloom shrinks the real Dock
/// to exactly the bar's height and sits on top of it. Zoom, tiling and new window
/// placement then all stop at the top of the bar. The user's original Dock
/// settings come back on quit.
final class DockController {
    /// Dock reserves `tilesize + 20` points at the bottom of the screen.
    static let tileSize = Int(TaskbarWindow.defaultHeight) - 20

    private let domain = "com.apple.dock" as CFString
    private let savedKey = "savedDockSettings"

    private enum Kind { case bool, float, string }
    private let keys: [(String, Kind)] = [
        ("autohide", .bool),
        ("autohide-delay", .float),
        ("tilesize", .float),
        ("magnification", .bool),
        ("orientation", .string),
    ]

    private(set) var isManaged = false

    func reserveSpace() {
        let defaults = UserDefaults.standard
        // Only snapshot once: after a crash the live values are already ours.
        if defaults.dictionary(forKey: savedKey) == nil {
            var saved: [String: Any] = [:]
            for (key, _) in keys {
                if let value = CFPreferencesCopyAppValue(key as CFString, domain) {
                    saved[key] = value
                }
            }
            defaults.set(saved, forKey: savedKey)
        }
        defaultsCommand(["write", "com.apple.dock", "autohide", "-bool", "false"])
        defaultsCommand(["delete", "com.apple.dock", "autohide-delay"])
        defaultsCommand(["write", "com.apple.dock", "tilesize", "-int", String(Self.tileSize)])
        defaultsCommand(["write", "com.apple.dock", "magnification", "-bool", "false"])
        defaultsCommand(["write", "com.apple.dock", "orientation", "-string", "bottom"])
        relaunchDock()
        isManaged = true
    }

    func restore() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.dictionary(forKey: savedKey) else { return }
        for (key, kind) in keys {
            guard let value = saved[key] else {
                defaultsCommand(["delete", "com.apple.dock", key])
                continue
            }
            switch kind {
            case .bool:
                defaultsCommand(["write", "com.apple.dock", key, "-bool", (value as? Bool ?? false) ? "true" : "false"])
            case .float:
                defaultsCommand(["write", "com.apple.dock", key, "-float", "\(value)"])
            case .string:
                defaultsCommand(["write", "com.apple.dock", key, "-string", "\(value)"])
            }
        }
        defaults.removeObject(forKey: savedKey)
        relaunchDock()
        isManaged = false
    }

    private func defaultsCommand(_ args: [String]) {
        run("/usr/bin/defaults", args)
    }

    private func relaunchDock() {
        run("/usr/bin/killall", ["Dock"])
    }

    private func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
