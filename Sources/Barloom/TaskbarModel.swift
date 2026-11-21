import AppKit
import Combine
import ServiceManagement

struct TaskItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let name: String
    let pinned: Bool
    let app: NSRunningApplication?

    var running: Bool { app != nil }

    static func == (a: TaskItem, b: TaskItem) -> Bool {
        a.id == b.id && a.pinned == b.pinned && a.app?.processIdentifier == b.app?.processIdentifier
    }
}

@MainActor
final class TaskbarModel: ObservableObject {
    @Published private(set) var items: [TaskItem] = []
    @Published private(set) var activePID: pid_t = 0
    @Published private(set) var battery: BatteryState?
    @Published var managesDock: Bool {
        didSet {
            UserDefaults.standard.set(managesDock, forKey: "managesDock")
            applyDockPreference()
        }
    }

    @Published var size: TaskbarSize {
        didSet {
            UserDefaults.standard.set(size.rawValue, forKey: TaskbarSize.defaultsKey)
            // Resize the Dock underneath so windows still stop at the bar's top edge.
            if managesDock { dock.reserveSpace() }
        }
    }

    enum ButtonMode: String, CaseIterable { case windows, apps }

    @Published var buttonMode: ButtonMode { didSet { store(buttonMode.rawValue, "buttonMode") } }
    @Published var showsTitles: Bool { didSet { store(showsTitles, "showsTitles") } }
    @Published var groupsByApp: Bool { didSet { store(groupsByApp, "groupsByApp") } }
    @Published var showsPreviews: Bool { didSet { store(showsPreviews, "showsPreviews") } }
    @Published var centersButtons: Bool { didSet { store(centersButtons, "centersButtons") } }
    @Published private(set) var recents: [URL] = []

    let dock = DockController()

    private var pinnedPaths: [String]
    private var bundleIDs: [String: String] = [:]
    private var desktopStash: [NSRunningApplication] = []
    private var observers: [NSObjectProtocol] = []
    private var batteryTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "pinnedApps") {
            pinnedPaths = saved
        } else {
            pinnedPaths = AppCatalog.defaultPinned().map(\.path)
            defaults.set(pinnedPaths, forKey: "pinnedApps")
        }
        managesDock = defaults.object(forKey: "managesDock") as? Bool ?? true
        size = .current
        buttonMode = defaults.string(forKey: "buttonMode").flatMap(ButtonMode.init) ?? .windows
        showsTitles = defaults.object(forKey: "showsTitles") as? Bool ?? true
        groupsByApp = defaults.object(forKey: "groupsByApp") as? Bool ?? false
        showsPreviews = defaults.object(forKey: "showsPreviews") as? Bool ?? true
        centersButtons = defaults.object(forKey: "centersButtons") as? Bool ?? false
        recents = (defaults.stringArray(forKey: "recentApps") ?? []).map { URL(fileURLWithPath: $0) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.noteRecent(app) }
        })

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }

        battery = .current()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.battery = .current() }
        }
        refresh()
    }

    func applyDockPreference() {
        if managesDock, !dock.isManaged {
            dock.reserveSpace()
        } else if !managesDock {
            dock.restore()
        }
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func noteRecent(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, let url = app.bundleURL,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        var list = recents.filter { $0.path != url.path }
        list.insert(url, at: 0)
        recents = Array(list.prefix(6))
        UserDefaults.standard.set(recents.map(\.path), forKey: "recentApps")
    }

    // MARK: - State

    func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleURL != nil
        }
        var byID: [String: NSRunningApplication] = [:]
        var byPath: [String: NSRunningApplication] = [:]
        for app in running {
            if let id = app.bundleIdentifier, byID[id] == nil { byID[id] = app }
            if let path = app.bundleURL?.path, byPath[path] == nil { byPath[path] = app }
        }

        var result: [TaskItem] = []
        var claimed = Set<pid_t>()
        for path in pinnedPaths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            // Match on bundle ID too: Safari runs from a cryptex path, not /Applications.
            let app = bundleID(for: url).flatMap { byID[$0] } ?? byPath[path]
            if let app { claimed.insert(app.processIdentifier) }
            result.append(TaskItem(id: path, url: url, name: AppCatalog.displayName(url), pinned: true, app: app))
        }
        for app in running where !claimed.contains(app.processIdentifier) {
            let url = app.bundleURL!
            result.append(TaskItem(
                id: "pid-\(app.processIdentifier)", url: url,
                name: app.localizedName ?? AppCatalog.displayName(url), pinned: false, app: app
            ))
        }

        if result != items { items = result }
        activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }

    func isActive(_ item: TaskItem) -> Bool {
        guard let app = item.app else { return false }
        return app.processIdentifier == activePID && !app.isHidden
    }

    private func bundleID(for url: URL) -> String? {
        if let hit = bundleIDs[url.path] { return hit }
        let id = Bundle(url: url)?.bundleIdentifier
        bundleIDs[url.path] = id
        return id
    }

    // MARK: - Actions

    /// Windows semantics: clicking the focused app minimises (hides) it,
    /// anything else brings it forward or launches it.
    func click(_ item: TaskItem) {
        desktopStash.removeAll()
        if isActive(item), let app = item.app {
            app.hide()
        } else {
            open(item.url)
        }
    }

    func open(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    func quit(_ item: TaskItem) {
        item.app?.terminate()
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedPaths.contains(url.path)
    }

    func pin(_ url: URL) {
        guard !isPinned(url) else { return }
        pinnedPaths.append(url.path)
        savePins()
    }

    func unpin(_ url: URL) {
        pinnedPaths.removeAll { $0 == url.path }
        savePins()
    }

    func movePin(_ path: String, before target: String) {
        guard path != target, let from = pinnedPaths.firstIndex(of: path) else { return }
        pinnedPaths.remove(at: from)
        let to = pinnedPaths.firstIndex(of: target) ?? pinnedPaths.endIndex
        pinnedPaths.insert(path, at: to)
        savePins()
    }

    private func savePins() {
        UserDefaults.standard.set(pinnedPaths, forKey: "pinnedApps")
        refresh()
    }

    /// The sliver at the far right: hide everything, click again to bring it back.
    func toggleDesktop() {
        if !desktopStash.isEmpty {
            desktopStash.forEach { $0.unhide() }
            desktopStash.removeAll()
            return
        }
        desktopStash = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden
        }
        desktopStash.forEach { $0.hide() }
    }

    // MARK: - Login item

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            objectWillChange.send()
        }
    }
}
