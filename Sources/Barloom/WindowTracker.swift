import AppKit
import ApplicationServices

/// Private but long-stable SPI (used by AltTab, Taskbar, yabai…) mapping an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    let appURL: URL
    let appName: String
    var title: String
    var isMinimized: Bool
    var isAppHidden: Bool
    var displayID: CGDirectDisplayID

    var displayTitle: String { title.isEmpty ? appName : title }

    static func == (a: WindowInfo, b: WindowInfo) -> Bool {
        a.id == b.id && a.title == b.title && a.isMinimized == b.isMinimized
            && a.isAppHidden == b.isAppHidden && a.displayID == b.displayID
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Lists the standard windows on the current Space through the Accessibility API
/// and keeps the list live with AX observers.
@MainActor
final class WindowTracker: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var focusedID: CGWindowID?
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var order: [CGWindowID] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var rescanQueued = false
    private var trustTimer: Timer?
    private var safetyTimer: Timer?

    init() {
        // One hung app must not freeze the taskbar.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRescan() }
            }
        }
        // Launching apps register windows a beat after the launch notification,
        // and a few apps never post AX notifications at all.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        }
        if !isTrusted { watchForTrust() }
        rescan()
    }

    // MARK: - Permission

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted {
            Power.openSettings("com.apple.preference.security?Privacy_Accessibility")
            watchForTrust()
        }
    }

    private func watchForTrust() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.trustTimer = nil
                self.isTrusted = true
                self.rescan()
            }
        }
    }

    // MARK: - Scanning

    func scheduleRescan() {
        guard !rescanQueued else { return }
        rescanQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            self.rescanQueued = false
            self.rescan()
        }
    }

    private func rescan() {
        guard isTrusted else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && $0.bundleURL != nil
        }
        syncObservers(apps)

        var found: [CGWindowID: WindowInfo] = [:]
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            for element in axArray(axApp, kAXWindowsAttribute) {
                guard axString(element, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) else { continue }
                var id: CGWindowID = 0
                guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { continue }
                found[id] = WindowInfo(
                    id: id, pid: app.processIdentifier, element: element,
                    appURL: app.bundleURL!, appName: app.localizedName ?? "",
                    title: axString(element, kAXTitleAttribute) ?? "",
                    isMinimized: axBool(element, kAXMinimizedAttribute),
                    isAppHidden: app.isHidden,
                    displayID: displayID(of: element)
                )
            }
        }

        // Keep the user's order; new windows join at the right end.
        order.removeAll { found[$0] == nil }
        for id in found.keys.sorted() where !order.contains(id) { order.append(id) }
        let result = order.compactMap { found[$0] }
        if result != windows { windows = result }

        var focused: CGWindowID?
        if let front = NSWorkspace.shared.frontmostApplication,
           let element = axElement(AXUIElementCreateApplication(front.processIdentifier), kAXFocusedWindowAttribute) {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(element, &id) == .success { focused = id }
        }
        if focused != focusedID { focusedID = focused }
    }

    private func displayID(of element: AXUIElement) -> CGDirectDisplayID {
        guard let origin = axPoint(element, kAXPositionAttribute),
              let size = axSize(element, kAXSizeAttribute),
              let primary = NSScreen.screens.first
        else { return NSScreen.main?.displayID ?? 0 }
        // AX uses top-left origin coordinates relative to the primary display.
        let center = NSPoint(x: origin.x + size.width / 2, y: primary.frame.maxY - origin.y - size.height / 2)
        return (NSScreen.screens.first { $0.frame.contains(center) } ?? primary).displayID
    }

    // MARK: - Observers

    private func syncObservers(_ apps: [NSRunningApplication]) {
        let live = Set(apps.map(\.processIdentifier))
        for (pid, observer) in observers where !live.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = nil
        }
        for pid in live where observers[pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for note in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
                         kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                         kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
                         kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification] {
                AXObserverAddNotification(observer, axApp, note as CFString, refcon)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = observer
        }
    }

    // MARK: - Actions

    /// Windows semantics: click switches to the window, clicking the focused one minimises it.
    func click(_ window: WindowInfo) {
        if window.id == focusedID, !window.isMinimized, !window.isAppHidden,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid {
            minimize(window)
        } else {
            focus(window)
        }
    }

    func focus(_ window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if app.isHidden { app.unhide() }
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        // A background accessory app can't reliably activate others directly;
        // going through Launch Services can, and the raised window stays on top.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: window.appURL, configuration: config)
        focusedID = window.id
    }

    func minimize(_ window: WindowInfo) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        scheduleRescan()
    }

    func close(_ window: WindowInfo) {
        if let button = axElement(window.element, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
        scheduleRescan()
    }

    func move(_ id: CGWindowID, before target: CGWindowID) {
        guard id != target, let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: order.firstIndex(of: target) ?? order.endIndex)
        windows = order.compactMap { id in windows.first { $0.id == id } }
    }
}

private let axCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { tracker.scheduleRescan() }
}

// MARK: - AX helpers

private func axValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    axValue(element, attribute) as? String
}

private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
    (axValue(element, attribute) as? Bool) ?? false
}

private func axArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    (axValue(element, attribute) as? [AXUIElement]) ?? []
}

private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = axValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = axValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
}

private func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let value = axValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
}
