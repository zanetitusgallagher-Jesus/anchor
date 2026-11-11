import AnchorCore
import AppKit
import SwiftUI

/// Calm, reverent palette: parchment by day, warm charcoal for early mornings.
enum Theme {
    static let background = dynamic(light: 0xF6F0E4, dark: 0x1A1917)
    static let surface = dynamic(light: 0xFBF8F1, dark: 0x24221F)
    static let ink = dynamic(light: 0x2B2620, dark: 0xE9E2D3)
    static let secondaryInk = dynamic(light: 0x6E655A, dark: 0xA79F92)
    static let accent = dynamic(light: 0x9A6B2F, dark: 0xD3A867)
    static let hairline = dynamic(light: 0xE2D8C6, dark: 0x3A3631)
    static let heat = dynamic(light: 0x9A6B2F, dark: 0xD3A867)

    static func scripture(_ settings: AnchorSettings, scale: Double = 1) -> Font {
        let size = settings.scriptureFontSize * scale
        switch settings.scriptureFont {
        case .newYork: return .system(size: size, weight: .regular, design: .serif)
        case .iowanOldStyle: return .custom("Iowan Old Style", size: size)
        }
    }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }

    static func colorScheme(_ pref: AppearancePreference) -> ColorScheme? {
        switch pref {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func nsAppearance(_ pref: AppearancePreference) -> NSAppearance? {
        switch pref {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A soft card used throughout the gate and dashboard.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .foregroundStyle(Theme.background)
            .background(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: Capsule())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondaryInk.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

/// Multi-line text field styled for the parchment theme.
struct ParchmentEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Theme.secondaryInk.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 8)
        }
        .font(.system(size: 15, design: .serif))
        .foregroundStyle(Theme.ink)
        .frame(minHeight: minHeight)
        .padding(.horizontal, 8)
        .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
    }
}

extension Int {
    /// 125 -> "2:05"
    var clockString: String { String(format: "%d:%02d", self / 60, self % 60) }
}
