import AppKit
import AVFoundation
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// Windows 11 "Mica": a heavily blurred, tinted slice of the wallpaper.
/// Opaque on purpose, so the shrunken Dock underneath never shows through.
struct MicaBackground: View {
    let screen: NSScreen
    @State private var wallpaper: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .transition(.opacity)
            }
            Color(nsColor: .windowBackgroundColor).opacity(0.72)
        }
        .task { await reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        let image = await Mica.strip(for: screen, height: TaskbarWindow.height(for: screen))
        withAnimation(.easeOut(duration: 0.3)) { wallpaper = image }
    }
}

enum Mica {
    private static let context = CIContext()

    static func strip(for screen: NSScreen, height: CGFloat) async -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = await loadImage(url)
        else { return nil }

        let size = screen.frame.size
        var image = CIImage(cgImage: source)
        // Aspect-fill the screen, like the desktop does, then keep the bottom strip.
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: -(image.extent.width - size.width) / 2,
            y: -(image.extent.height - size.height) / 2
        ))
        let strip = CGRect(x: 0, y: 0, width: size.width, height: height)
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 36).cropped(to: strip)
        guard let output = context.createCGImage(blurred, from: strip) else { return nil }
        return NSImage(cgImage: output, size: strip.size)
    }

    private static func loadImage(_ url: URL) async -> CGImage? {
        // Live wallpapers (Muro and friends) point at a movie; use its first frame.
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1600, height: 1600)
            return try? await generator.image(at: .zero).image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ] as CFDictionary)
    }
}
