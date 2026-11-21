import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TaskbarModel()
    private lazy var flyouts = FlyoutController(model: model)
    private var bars: [TaskbarWindow] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var sizeObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.applyDockPreference()
        rebuildBars()
        // The relaunched Dock takes a moment to claim its strip of the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.rebuildBars()
        }

        sizeObserver = model.$size.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.rebuildBars()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.rebuildBars() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildBars() }
        }

        // Lets hotkey tools (skhd, Raycast, Shortcuts) act as a Windows key.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.qwelpl.barloom.toggleStart"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                    ?? NSScreen.main ?? NSScreen.screens[0]
                self.flyouts.toggle(.start, on: screen)
            }
        }

        // `kill`/Ctrl-C should still give the Dock back.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.dock.restore()
    }

    private func rebuildBars() {
        flyouts.close(animated: false)
        bars.forEach { $0.orderOut(nil) }
        bars = NSScreen.screens.map { screen in
            let bar = TaskbarWindow(
                screen: screen,
                root: TaskbarView(model: model, flyouts: flyouts, screen: screen)
            )
            bar.orderFrontRegardless()
            return bar
        }
    }
}
