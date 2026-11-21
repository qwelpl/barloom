import AppKit

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

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let hit = cache[url.path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }
}
