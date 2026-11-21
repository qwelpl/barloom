import Foundation

/// Pushes the macOS Dock out of the way (auto-hide with an effectively infinite
/// reveal delay) and puts the user's original settings back on quit.
final class DockController {
    private let domain = "com.apple.dock" as CFString
    private let savedKey = "savedDockState"

    private(set) var isHidden = false

    func hide() {
        let defaults = UserDefaults.standard
        // Only snapshot once: after a crash the live values are already ours.
        if defaults.dictionary(forKey: savedKey) == nil {
            var saved: [String: Any] = [:]
            if let autohide = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool {
                saved["autohide"] = autohide
            }
            if let delay = CFPreferencesCopyAppValue("autohide-delay" as CFString, domain) as? Double {
                saved["autohide-delay"] = delay
            }
            defaults.set(saved, forKey: savedKey)
        }
        write(["write", "com.apple.dock", "autohide", "-bool", "true"])
        write(["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        relaunchDock()
        isHidden = true
    }

    func restore() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.dictionary(forKey: savedKey) else { return }
        if let autohide = saved["autohide"] as? Bool {
            write(["write", "com.apple.dock", "autohide", "-bool", autohide ? "true" : "false"])
        } else {
            write(["delete", "com.apple.dock", "autohide"])
        }
        if let delay = saved["autohide-delay"] as? Double {
            write(["write", "com.apple.dock", "autohide-delay", "-float", String(delay)])
        } else {
            write(["delete", "com.apple.dock", "autohide-delay"])
        }
        defaults.removeObject(forKey: savedKey)
        relaunchDock()
        isHidden = false
    }

    private func write(_ args: [String]) {
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
