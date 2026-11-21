import AppKit
import SwiftUI

struct AppEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: String { url.path }
}

enum AppCatalog {
    static let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    /// Finder plus whatever the user had pinned in the macOS Dock.
    static func defaultPinned() -> [URL] {
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString)
            as? [[String: Any]] ?? []
        let dockApps = tiles.compactMap { tile -> URL? in
            let fileData = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
            guard let string = fileData?["_CFURLString"] as? String,
                  let url = URL(string: string), url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            return url
        }
        return [finder] + dockApps.filter { $0.path != finder.path }
    }

    static func allApps() -> [AppEntry] {
        let fm = FileManager.default
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var entries: [AppEntry] = []

        func add(_ url: URL) {
            let name = displayName(url)
            guard seen.insert(name.lowercased()).inserted else { return }
            entries.append(AppEntry(url: url, name: name))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let children = try? fm.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    add(child)
                } else if root == "/Applications",
                          (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          child.lastPathComponent != "Utilities" {
                    // Vendor folders such as /Applications/Adobe Photoshop/.
                    let nested = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                    nested.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        add(finder)
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Installed apps, scanned off the main thread so the Start menu opens instantly.
@MainActor
final class AppLibrary: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    init() { reload() }

    func reload() {
        Task.detached(priority: .utility) {
            let apps = AppCatalog.allApps()
            await MainActor.run {
                if apps != self.apps { self.apps = apps }
            }
        }
    }
}

/// App icons rendered once at their exact on-screen pixel size. Letting SwiftUI
/// shrink the 1024px source every frame is both slow and visibly aliased,
/// especially on 1x displays.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL, size: CGFloat, scale: CGFloat) -> NSImage {
        let key = "\(url.path)|\(size)|\(scale)"
        if let hit = cache[key] { return hit }

        let source = NSWorkspace.shared.icon(forFile: url.path)
        let pixels = Int((size * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return source }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        context?.imageInterpolation = .high
        NSGraphicsContext.current = context
        // NSImage picks its hand-tuned representation closest to `pixels` (e.g. the native 32px one).
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
                    operation: .copy, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        cache[key] = image
        return image
    }
}

struct AppIcon: View {
    let url: URL
    let size: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        Image(nsImage: IconCache.icon(for: url, size: size, scale: scale))
            .frame(width: size, height: size)
    }
}
