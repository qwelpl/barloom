import CoreGraphics
import Foundation

enum TaskbarSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    static let defaultsKey = "taskbarSize"

    static var current: TaskbarSize {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(TaskbarSize.init) ?? .medium
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var barHeight: CGFloat {
        switch self {
        case .small: 40
        case .medium: 48
        case .large: 60
        case .extraLarge: 72
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: 24
        case .medium: 32
        case .large: 40
        case .extraLarge: 48
        }
    }

    var buttonSize: CGFloat { iconSize + 12 }
    var glyphSize: CGFloat { iconSize * 0.7 }
    var trayFontSize: CGFloat { self == .small ? 11 : 11 + (iconSize - 32) / 16 + 0.5 }
}
