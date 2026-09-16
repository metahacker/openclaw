import SwiftUI
import UIKit

/// Mark's MVP UI visual system (composite of September 8, chat viewport of August 18).
/// Values were sampled from those screens; dark mode stays in the same cream/ink family.
enum OLSTheme {
    static let background = color(0xF5F1E8, dark: 0x1A1D18)
    static let header = color(0xF7F5ED, dark: 0x1E221C)
    static let paper = color(0xFFFFFF, dark: 0x262B24)
    static let ink = color(0x1E251E, dark: 0xF3F0E8)
    static let secondary = color(0x5B6455, dark: 0xB7BFAF)
    static let line = color(0xE5E7EB, dark: 0x3A4036)
    static let cardLine = color(0xE6E9E1, dark: 0x3A4036)
    static let accent = color(0x4F6B3F, dark: 0xC9E39A)
    static let human = color(0xEDF4DF, dark: 0x36432B)
    static let soft = color(0xE8E5DD, dark: 0x30352C)
    static let sendArrow = color(0x8C877A, dark: 0xD9D4C7)
    static let warning = color(0x88622A, dark: 0xE9BD72)

    /// Lora ships in the bundle (OFL); the serif design falls back to New York if the
    /// font fails to register so the composition still reads as Mark's.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        if UIFont(name: "Lora-Regular", size: size) != nil {
            return Font.custom("Lora", size: size, relativeTo: style)
        }
        return Font.system(size: size, weight: .regular, design: .serif)
    }

    static let greeting = serif(36, relativeTo: .largeTitle)
    static let title = serif(30, relativeTo: .title)
    static let heading = serif(24, relativeTo: .title2)
    static let cardTitle = serif(21, relativeTo: .title3)
    static let rowTitle = serif(18, relativeTo: .headline)
    static let wordmark = Font.system(size: 30, weight: .medium, design: .rounded)
    static let body = Font.custom("Inter", size: 17, relativeTo: .body)
    static let label = Font.custom("Inter", size: 15, relativeTo: .subheadline)
    static let action = Font.custom("Inter", size: 15, relativeTo: .subheadline).weight(.semibold)
    static let caption = Font.custom("Inter", size: 12, relativeTo: .caption)
    static let kicker = Font.custom("Inter", size: 12, relativeTo: .caption).weight(.bold)
    static let timestamp = Font.custom("Inter", size: 11, relativeTo: .caption2)
    static let chip = Font.custom("JetBrainsMono-Regular", size: 12, relativeTo: .caption)

    /// Letterspacing for the small-caps kickers (`MONDAY · AUGUST 17`, `THIS MORNING`).
    static let kickerTracking: CGFloat = 1.6

    /// UIKit twin of `body` for the UITextView-backed editors.
    static var bodyUIFont: UIFont {
        let base = UIFont(name: "Inter-Regular", size: 17) ?? UIFont.systemFont(ofSize: 17)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    private static func color(_ light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255,
                alpha: 1)
        })
    }
}

/// `MONDAY · AUGUST 17`, `DETAILS`, `JAPAN FAMILY TRIP`: uppercase, letterspaced, grey.
struct OLSKicker: View {
    var text: String
    var color: Color = OLSTheme.secondary

    var body: some View {
        Text(self.text.uppercased())
            .font(OLSTheme.kicker)
            .tracking(OLSTheme.kickerTracking)
            .foregroundStyle(self.color)
    }
}

struct OLSCardSurface: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(self.padding)
            .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: self.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: self.radius, style: .continuous)
                    .strokeBorder(OLSTheme.cardLine, lineWidth: 1)
            }
    }
}

extension View {
    func olsCard(padding: CGFloat = 20, radius: CGFloat = 24) -> some View {
        self.modifier(OLSCardSurface(padding: padding, radius: radius))
    }
}
