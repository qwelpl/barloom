import AppKit
import SwiftUI

/// Hosting view that reacts to the first click even though Barloom never activates.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class TaskbarWindow: NSPanel {
    static var defaultHeight: CGFloat { TaskbarSize.current.barHeight }

    /// Covers whatever strip the (shrunken) Dock reserves, so windows stop at our top edge.
    static func height(for screen: NSScreen) -> CGFloat {
        max(defaultHeight, screen.visibleFrame.minY - screen.frame.minY)
    }

    init<Content: View>(screen: NSScreen, root: Content) {
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                           width: screen.frame.width, height: Self.height(for: screen))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // One above the Dock, which sits underneath us.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        contentView = FirstMouseHostingView(rootView: root)
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FlyoutPanel: NSPanel {
    var onCancel: (() -> Void)?

    init<Content: View>(size: NSSize, root: Content) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = FirstMouseHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

@MainActor
final class FlyoutController: ObservableObject {
    enum Kind { case start, calendar }

    @Published private(set) var openKind: Kind?

    private let model: TaskbarModel
    private let library = AppLibrary()
    private var panel: FlyoutPanel?
    private var clickMonitor: Any?

    init(model: TaskbarModel) {
        self.model = model
    }

    func toggle(_ kind: Kind, on screen: NSScreen) {
        if openKind == kind {
            close()
        } else {
            close(animated: false)
            show(kind, on: screen)
        }
    }

    private func show(_ kind: Kind, on screen: NSScreen) {
        let size: NSSize
        let root: AnyView
        let dismiss: () -> Void = { [weak self] in self?.close() }
        switch kind {
        case .start:
            library.reload()
            size = NSSize(width: 640, height: 700)
            root = AnyView(FlyoutChrome { StartMenuView(model: self.model, library: self.library, dismiss: dismiss) })
        case .calendar:
            size = NSSize(width: 340, height: 392)
            root = AnyView(FlyoutChrome { CalendarFlyoutView() })
        }

        let panel = FlyoutPanel(size: size, root: root)
        panel.onCancel = dismiss
        let bottom = screen.frame.minY + TaskbarWindow.height(for: screen) + 12
        let x = kind == .start
            ? screen.frame.midX - size.width / 2
            : screen.frame.maxX - size.width - 12
        let target = NSRect(x: x, y: bottom, width: size.width, height: size.height)

        // Only the alpha animates at the window level; the slide happens inside
        // SwiftUI (FlyoutChrome) so the window server never re-shadows a moving window.
        panel.setFrame(target, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak panel] in
            panel?.invalidateShadow()
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        self.panel = panel
        openKind = kind
    }

    func close(animated: Bool = true) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        openKind = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

struct FlyoutChrome<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffect(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .offset(y: shown ? 0 : 36)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { shown = true }
            }
    }
}

/// Subtle Fluent-style hover/press plate.
struct PlateButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6
    var selected = false
    var pressScale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        Plate(configuration: configuration, style: self)
    }

    private struct Plate: View {
        let configuration: Configuration
        let style: PlateButtonStyle
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(fill))
                )
                .scaleEffect(configuration.isPressed ? style.pressScale : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }

        private var fill: Double {
            if configuration.isPressed { return 0.05 }
            if hovering { return 0.1 }
            return style.selected ? 0.07 : 0
        }
    }
}
