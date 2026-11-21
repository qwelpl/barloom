import AppKit
import IOKit.ps

struct BatteryState: Equatable {
    let percent: Int
    let charging: Bool
    let onAC: Bool

    static func current() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return BatteryState(
                percent: Int((Double(capacity) / Double(max) * 100).rounded()),
                charging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                onAC: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }

    var symbol: String {
        if charging || onAC { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

enum Power {
    static func sleep() { run("/usr/bin/pmset", ["sleepnow"]) }
    static func displayOff() { run("/usr/bin/pmset", ["displaysleepnow"]) }
    // loginwindow shows its own confirmation dialog for each of these.
    static func logOut() { loginwindow("logo") }
    static func restart() { loginwindow("rrst") }
    static func shutDown() { loginwindow("rsdn") }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func loginwindow(_ code: String) {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevt\(code)»")?
            .executeAndReturnError(&error)
    }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
    }
}
