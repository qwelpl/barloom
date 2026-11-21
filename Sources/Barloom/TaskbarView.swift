import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskbarView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var flyouts: FlyoutController
    let screen: NSScreen

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                StartButton(isOpen: flyouts.openKind == .start) {
                    flyouts.toggle(.start, on: screen)
                }
                ForEach(model.items) { item in
                    TaskIcon(item: item, model: model, isActive: model.isActive(item)) {
                        flyouts.close()
                    }
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: model.items.map(\.id))

            HStack(spacing: 0) {
                Spacer()
                TrayView(model: model, flyouts: flyouts, screen: screen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect(material: .menu))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }
}

private struct StartButton: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.macro")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.62),
                                            Color(red: 0.55, green: 0.4, blue: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 40, height: 40)
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
                Image(nsImage: IconCache.icon(for: item.url))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                    .frame(width: 40, height: 40)
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
                guard let path = object as? String else { return }
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
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(battery.percent <= 15 && !battery.onAC ? Color.red : Color.primary)
                        .frame(width: 34, height: 40)
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
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .frame(height: 40)
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
            .frame(height: TaskbarWindow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .onHover { hovering = $0 }
        .help("Show desktop")
    }
}
