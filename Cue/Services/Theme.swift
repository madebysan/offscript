import AppKit
import SwiftUI

/// Colors for the prompter window. `system` follows the Mac's light or dark mode.
enum PrompterTheme: String, CaseIterable, Identifiable {
    case system, dark, light, sepia, midnight, classic, yellow, blue

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "Match System"
        case .dark: return "Dark"
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .midnight: return "Midnight"
        case .classic: return "Classic"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        }
    }

    /// The appearance for the window's controls; nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light, .sepia, .yellow: return NSAppearance(named: .aqua)
        case .dark, .midnight, .classic, .blue: return NSAppearance(named: .darkAqua)
        }
    }

    /// `system` resolved against the window's current appearance.
    func resolved(for scheme: ColorScheme) -> PrompterTheme {
        guard self == .system else { return self }
        return scheme == .dark ? .dark : .light
    }

    var background: NSColor {
        switch self {
        case .system, .dark: return .black
        case .light: return NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1)
        case .sepia: return NSColor(srgbRed: 0.96, green: 0.93, blue: 0.85, alpha: 1)
        case .midnight: return NSColor(srgbRed: 0.06, green: 0.10, blue: 0.17, alpha: 1)
        case .classic: return .black
        case .yellow: return NSColor(srgbRed: 1.0, green: 0.85, blue: 0.20, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.13, green: 0.35, blue: 0.90, alpha: 1)
        }
    }

    var text: NSColor {
        switch self {
        case .system, .dark: return NSColor(white: 0.95, alpha: 1)
        case .light: return NSColor(white: 0.10, alpha: 1)
        case .sepia: return NSColor(srgbRed: 0.26, green: 0.20, blue: 0.13, alpha: 1)
        case .midnight: return NSColor(srgbRed: 0.86, green: 0.90, blue: 0.95, alpha: 1)
        case .classic: return NSColor(srgbRed: 1.0, green: 0.84, blue: 0.04, alpha: 1)
        case .yellow: return NSColor(white: 0.07, alpha: 1)
        case .blue: return .white
        }
    }
}

/// Fonts for the script: a short list of fonts that ship with macOS and read
/// well at a distance. The first four are macOS system designs.
enum PrompterFont {
    static let system = "System"
    static let choices = ["System", "Rounded", "Serif", "Monospaced", "Avenir Next", "Helvetica Neue", "Georgia", "Charter"]

    /// A saved font that's no longer offered shows as System.
    static func choice(_ saved: String) -> String { choices.contains(saved) ? saved : system }

    static func font(_ choice: String, size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let design: NSFontDescriptor.SystemDesign?
        switch choice {
        case "System": return base
        case "Rounded": design = .rounded
        case "Serif": design = .serif
        case "Monospaced": design = .monospaced
        default: design = nil
        }
        if let design {
            return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        // A named family; falls back to the system font if it's missing
        return NSFontManager.shared.font(withFamily: choice, traits: [], weight: 5, size: size) ?? base
    }
}
