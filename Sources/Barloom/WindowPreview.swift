import AppKit
import ScreenCaptureKit
import SwiftUI

enum WindowCapture {
    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Registers Barloom in the Screen Recording list, then opens that settings page
    /// so the user can switch it on. macOS only applies the grant after a relaunch.
    static func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
        Power.openSettings("com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func thumbnail(of id: CGWindowID, fitting box: CGSize, scale: CGFloat) async -> NSImage? {
        guard hasAccess,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == id }),
              window.frame.width > 0, window.frame.height > 0
        else { return nil }

        let fit = min(box.width / window.frame.width, box.height / window.frame.height)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * fit * scale))
        config.height = max(1, Int(window.frame.height * fit * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config
        ) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: window.frame.width * fit, height: window.frame.height * fit))
    }
}

/// Hover a window button to see a live thumbnail of that window above it.
@MainActor
final class PreviewController: ObservableObject {
    static let size = NSSize(width: 268, height: 206)

    @Published private(set) var window: WindowInfo?
    private(set) var hoveredWindowID: CGWindowID?

    private let tracker: WindowTracker
    private let model: TaskbarModel
    private var panel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    init(tracker: WindowTracker, model: TaskbarModel) {
        self.tracker = tracker
        self.model = model
    }

    func hoverChanged(_ window: WindowInfo, hovering: Bool, anchorX: CGFloat, screen: NSScreen) {
        if hovering {
            hoveredWindowID = window.id
            hideWork?.cancel()
            showWork?.cancel()
            guard model.showsPreviews else { return }
            if panel?.isVisible == true {
                show(window, anchorX: anchorX, screen: screen)
            } else {
                let work = DispatchWorkItem { [weak self] in self?.show(window, anchorX: anchorX, screen: screen) }
                showWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
            }
        } else {
            if hoveredWindowID == window.id { hoveredWindowID = nil }
            showWork?.cancel()
            scheduleHide()
        }
    }

    func panelHover(_ hovering: Bool) {
        if hovering { hideWork?.cancel() } else { scheduleHide() }
    }

    func hide() {
        showWork?.cancel()
        hideWork?.cancel()
        panel?.orderOut(nil)
        window = nil
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func show(_ window: WindowInfo, anchorX: CGFloat, screen: NSScreen) {
        self.window = window
        let panel = self.panel ?? makePanel()
        let size = Self.size
        let x = min(max(anchorX - size.width / 2, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let y = screen.frame.minY + TaskbarWindow.height(for: screen) + 8
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = FirstMouseHostingView(rootView: PreviewCard(controller: self, tracker: tracker))
        self.panel = panel
        return panel
    }
}

private struct PreviewCard: View {
    @ObservedObject var controller: PreviewController
    let tracker: WindowTracker

    @State private var image: NSImage?
    @State private var closeHover = false
    @Environment(\.displayScale) private var scale

    private let box = CGSize(width: 244, height: 150)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let window = controller.window {
                HStack(spacing: 8) {
                    AppIcon(url: window.appURL, size: 16)
                    Text(window.displayTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Button {
                        tracker.close(window)
                        controller.hide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 4).fill(closeHover ? Color.red : Color.clear))
                            .foregroundStyle(closeHover ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { closeHover = $0 }
                    .help("Close window")
                }

                if !WindowCapture.hasAccess {
                    // Kept outside the thumbnail button so the click isn't swallowed by "switch to window".
                    Button {
                        controller.hide()
                        WindowCapture.requestAccess()
                    } label: {
                        VStack(spacing: 10) {
                            AppIcon(url: window.appURL, size: 48)
                            Text("Allow Screen Recording for previews")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            Text("Opens System Settings")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: box.width, height: box.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlateButtonStyle())
                } else {
                    Button {
                        tracker.focus(window)
                        controller.hide()
                    } label: {
                        ZStack {
                            if let image {
                                Image(nsImage: image)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            } else {
                                AppIcon(url: window.appURL, size: 48).opacity(window.isMinimized ? 0.6 : 1)
                            }
                        }
                        .frame(width: box.width, height: box.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onHover { controller.panelHover($0) }
        .task(id: controller.window?.id) {
            image = nil
            guard let id = controller.window?.id else { return }
            image = await WindowCapture.thumbnail(of: id, fitting: box, scale: scale)
        }
    }
}
