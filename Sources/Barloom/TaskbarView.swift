import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskbarView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var flyouts: FlyoutController
    @ObservedObject var tracker: WindowTracker
    let previews: PreviewController
    let screen: NSScreen

    @State private var trayWidth: CGFloat = 200

    enum Entry: Identifiable {
        case app(TaskItem)
        case window(WindowInfo)

        var id: String {
            switch self {
            case .app(let item): "app-\(item.id)"
            case .window(let window): "win-\(window.id)"
            }
        }
    }

    private var windowMode: Bool { model.buttonMode == .windows && tracker.isTrusted }

    /// Windows mode: one button per window on this display, pinned apps keep their slot
    /// (as their windows, or as a launcher icon when they have none). Apps mode: one icon per app.
    private var entries: [Entry] {
        guard windowMode else { return model.items.map(Entry.app) }
        let single = NSScreen.screens.count == 1
        let mine = tracker.windows.filter { single || $0.displayID == screen.displayID }
        var result: [Entry] = []
        var used = Set<CGWindowID>()
        for item in model.items where item.pinned {
            let windows = mine.filter { $0.pid == item.app?.processIdentifier }
            if windows.isEmpty {
                result.append(.app(item))
            } else {
                windows.forEach { result.append(.window($0)); used.insert($0.id) }
            }
        }
        var rest = mine.filter { !used.contains($0.id) }
        if model.groupsByApp {
            var first: [pid_t: Int] = [:]
            for (index, window) in rest.enumerated() where first[window.pid] == nil { first[window.pid] = index }
            rest = rest.enumerated()
                .sorted { (first[$0.element.pid]!, $0.offset) < (first[$1.element.pid]!, $1.offset) }
                .map(\.element)
        }
        return result + rest.map(Entry.window)
    }

    var body: some View {
        let entries = self.entries
        GeometryReader { proxy in
            let labelWidth = labelWidth(entries, barWidth: proxy.size.width)
            ZStack {
                if model.centersButtons { buttons(entries, labelWidth: labelWidth) }
                HStack(spacing: 0) {
                    if !model.centersButtons { buttons(entries, labelWidth: labelWidth).padding(.leading, 6) }
                    Spacer(minLength: 0)
                    TrayView(model: model, flyouts: flyouts, screen: screen)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trayWidth = $0 }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MicaBackground(screen: screen))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }

    private func buttons(_ entries: [Entry], labelWidth: CGFloat?) -> some View {
        HStack(spacing: 2) {
            StartButton(size: model.size, isOpen: flyouts.openKind == .start) {
                previews.hide()
                flyouts.toggle(.start, on: screen)
            }
            ForEach(entries) { entry in
                switch entry {
                case .app(let item):
                    TaskIcon(item: item, model: model, isActive: model.isActive(item)) {
                        flyouts.close()
                    }
                case .window(let window):
                    WindowButton(window: window, labelWidth: labelWidth,
                                 isFocused: tracker.focusedID == window.id,
                                 model: model, tracker: tracker, previews: previews, screen: screen) {
                        flyouts.close()
                    }
                }
            }
            if model.buttonMode == .windows && !tracker.isTrusted {
                Button { tracker.requestAccess() } label: {
                    Label("Allow window buttons", systemImage: "lock.shield")
                        .font(.system(size: model.size.trayFontSize + 0.5))
                        .padding(.horizontal, 10)
                        .frame(height: model.size.buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlateButtonStyle(selected: true))
                .help("Barloom needs Accessibility access to list and switch windows")
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: entries.map(\.id))
    }

    /// Titled buttons share whatever room the bar has left, up to a readable maximum,
    /// shrinking as windows pile up and falling back to icons only when they get too narrow.
    private func labelWidth(_ entries: [Entry], barWidth: CGFloat) -> CGFloat? {
        guard model.showsTitles else { return nil }
        let windows = entries.filter { if case .window = $0 { true } else { false } }.count
        guard windows > 0 else { return nil }
        let launchers = CGFloat(entries.count - windows + 1) * (model.size.buttonSize + 2)
        // Centered buttons must stay clear of the tray on both sides to remain centered.
        let free = model.centersButtons ? barWidth - 2 * (trayWidth + 12) : barWidth - trayWidth - 18
        let width = min(360, (free - launchers) / CGFloat(windows) - 2)
        return width >= 96 ? width.rounded(.down) : nil
    }
}

private struct StartButton: View {
    let size: TaskbarSize
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: size.glyphSize * 0.8, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: size.buttonSize, height: size.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle(selected: isOpen, pressScale: 0.86))
        .help("Start")
    }
}

private struct TaskIcon: View {
    let item: TaskItem
    @ObservedObject var model: TaskbarModel
    let isActive: Bool
    let willAct: () -> Void

    @State private var dropTargeted = false

    var body: some View {
        Button {
            willAct()
            model.click(item)
        } label: {
            ZStack(alignment: .bottom) {
                AppIcon(url: item.url, size: model.size.iconSize)
                    .frame(width: model.size.buttonSize, height: model.size.buttonSize)
                    .offset(y: -2)
                Capsule()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.85))
                    .frame(width: isActive ? 16 : 6, height: 3)
                    .opacity(item.running ? 1 : 0)
                    .padding(.bottom, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle(selected: isActive, pressScale: 0.86))
        .overlay(alignment: .leading) {
            if dropTargeted {
                Capsule().fill(Color.accentColor).frame(width: 2, height: 24).offset(x: -2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isActive)
        .animation(.easeOut(duration: 0.2), value: item.running)
        .help(item.name)
        .contextMenu { menu }
        .onDrag {
            NSItemProvider(object: item.url.path as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: $dropTargeted) { providers in
            guard item.pinned, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let path = object as? String, !path.hasPrefix("win:") else { return }
                DispatchQueue.main.async {
                    if !model.isPinned(URL(fileURLWithPath: path)) { model.pin(URL(fileURLWithPath: path)) }
                    model.movePin(path, before: item.id)
                }
            }
            return true
        }
    }

    @ViewBuilder private var menu: some View {
        Button(item.running ? "New Window" : "Open") { model.open(item.url) }
        Divider()
        if item.pinned {
            Button("Unpin from taskbar") { model.unpin(item.url) }
        } else {
            Button("Pin to taskbar") { model.pin(item.url) }
        }
        Button("Show in Finder") { model.revealInFinder(item.url) }
        if item.running {
            Divider()
            Button("Quit \(item.name)") { model.quit(item) }
        }
    }
}

private struct WindowButton: View {
    let window: WindowInfo
    let labelWidth: CGFloat?
    let isFocused: Bool
    @ObservedObject var model: TaskbarModel
    let tracker: WindowTracker
    let previews: PreviewController
    let screen: NSScreen
    let willAct: () -> Void

    @State private var frame: CGRect = .zero
    @State private var dropTargeted = false

    /// The focused window's underline spans its titled button; everything else keeps the small dot.
    private var indicatorWidth: CGFloat {
        guard isFocused else { return 6 }
        return labelWidth.map { $0 - 16 } ?? 16
    }

    private var iconSize: CGFloat {
        labelWidth == nil ? model.size.iconSize : (model.size.iconSize * 0.75).rounded()
    }

    var body: some View {
        Button {
            willAct()
            previews.hide()
            tracker.click(window)
        } label: {
            ZStack(alignment: .bottom) {
                HStack(spacing: 8) {
                    AppIcon(url: window.appURL, size: iconSize)
                    if labelWidth != nil {
                        Text(window.displayTitle)
                            .font(.system(size: model.size.trayFontSize + 0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, labelWidth == nil ? 0 : 10)
                .frame(width: labelWidth ?? model.size.buttonSize, height: model.size.buttonSize)
                .offset(y: labelWidth == nil ? -2 : -1)
                .opacity(window.isMinimized || window.isAppHidden ? 0.5 : 1)

                Capsule()
                    .fill(isFocused ? Color.accentColor : Color.secondary.opacity(0.85))
                    .frame(width: indicatorWidth, height: 3)
                    .padding(.bottom, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle(selected: isFocused, pressScale: 0.95))
        .overlay(alignment: .leading) {
            if dropTargeted {
                Capsule().fill(Color.accentColor).frame(width: 2, height: 24).offset(x: -2)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, new in frame = new }
        })
        .onHover { hovering in
            previews.hoverChanged(window, hovering: hovering,
                                  anchorX: screen.frame.minX + frame.midX, screen: screen)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isFocused)
        .help(model.showsPreviews ? "" : window.displayTitle)
        .contextMenu { menu }
        .onDrag { NSItemProvider(object: "win:\(window.id)" as NSString) }
        .onDrop(of: [.plainText], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String, string.hasPrefix("win:"),
                      let id = CGWindowID(string.dropFirst(4)) else { return }
                DispatchQueue.main.async { tracker.move(id, before: window.id) }
            }
            return true
        }
    }

    @ViewBuilder private var menu: some View {
        Button(window.isMinimized ? "Restore" : "Minimize") {
            window.isMinimized ? tracker.focus(window) : tracker.minimize(window)
        }
        Button("Close Window") { tracker.close(window) }
        Divider()
        Button("New \(window.appName) Window") { model.open(window.appURL) }
        if model.isPinned(window.appURL) {
            Button("Unpin from taskbar") { model.unpin(window.appURL) }
        } else {
            Button("Keep in taskbar") { model.pin(window.appURL) }
        }
        Divider()
        Button("Quit \(window.appName)") {
            NSRunningApplication(processIdentifier: window.pid)?.terminate()
        }
    }
}

private struct TrayView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var flyouts: FlyoutController
    let screen: NSScreen

    var body: some View {
        HStack(spacing: 2) {
            if let battery = model.battery {
                Button {
                    Power.openSettings("com.apple.Battery-Settings.extension")
                } label: {
                    Image(systemName: battery.symbol)
                        .font(.system(size: model.size.trayFontSize + 3))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(battery.percent <= 15 && !battery.onAC ? Color.red : Color.primary)
                        .frame(width: model.size.buttonSize - 8, height: model.size.buttonSize - 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlateButtonStyle())
                .help("Battery: \(battery.percent)%\(battery.charging ? " (charging)" : battery.onAC ? " (plugged in)" : "")")
            }

            Button {
                flyouts.toggle(.calendar, on: screen)
            } label: {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                        Text(context.date, format: .dateTime.month(.defaultDigits).day().year())
                    }
                    .font(.system(size: model.size.trayFontSize))
                    .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .frame(height: model.size.buttonSize - 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlateButtonStyle(selected: flyouts.openKind == .calendar))

            ShowDesktopSliver { model.toggleDesktop() }
        }
        .padding(.leading, 8)
    }
}

private struct ShowDesktopSliver: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(hovering ? 0.35 : 0.18))
                    .frame(width: 1, height: 16)
                Color.clear.frame(width: 9)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .onHover { hovering = $0 }
        .help("Show desktop")
    }
}
