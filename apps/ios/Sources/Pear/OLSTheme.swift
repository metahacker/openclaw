import SwiftUI
import UIKit

/// The September 4 One Living Surface prototype, light-first cascade (Study 05/06 in its
/// index.css). Every value here is the prototype's; dark mode stays in the same family.
enum OLSTheme {
    // Fields and chrome
    static let field = color(0xF6F2EA, dark: 0x171B16)
    static let workspaceField = color(0xF4F1E9, dark: 0x171B16)
    static let edge = color(0xECE8DE, dark: 0x20261F)
    static let paper = color(0xFFFFFF, dark: 0x252B24)
    static let spine = color(0xE7ECD9, dark: 0x222A20)
    static let spineLine = color(0xCFD5C4, dark: 0x3A4436)
    static let navActive = color(0xDFE9C7, dark: 0x33422A)
    static let projectCard = color(0xFBFAF6, dark: 0x252B24)
    static let projectCardLine = color(0xD8D6CD, dark: 0x3A4036)
    static let checkCard = color(0xFBFFF2, dark: 0x232B1E)
    static let tint = color(0xD6E99E, dark: 0x3D4B2A)
    // Ink
    static let ink = color(0x253025, dark: 0xF1F4EC)
    static let secondary = color(0x737B70, dark: 0xA9B3A4)
    static let muted = color(0x7A8176, dark: 0x8F998B)
    static let eyebrow = color(0x85917D, dark: 0x91A188)
    static let rule = color(0x9A9E97, dark: 0x7D857A)
    static let accent = color(0x77943A, dark: 0xC9F05C)
    static let warning = color(0x873B32, dark: 0xE9A08F)
    // Bubbles and controls
    static let human = color(0xDFF587, dark: 0x4C6224)
    static let humanInk = color(0x24301E, dark: 0xF1F4EC)
    static let presence = color(0x182219, dark: 0x0F150F)
    static let presenceMark = color(0xE4FF9C, dark: 0xE4FF9C)
    static let send = color(0x263226, dark: 0xD6FB70)
    static let sendInk = color(0xE7F8B6, dark: 0x172013)
    static let sendDisabled = color(0xE4E3DC, dark: 0x2E352C)
    static let sendDisabledInk = color(0x989C95, dark: 0x6F776C)
    static let decision = color(0xFFF4C9, dark: 0x3D351C)
    static let decisionLine = color(0xEADFAE, dark: 0x59461A)
    static let decisionLabel = color(0x9B5B13, dark: 0xF2C36B)
    static let decisionInk = color(0x59461A, dark: 0xF5E7B8)
    static let voiceDone = color(0xD9EF9B, dark: 0xD6FB70)
    static let voiceDoneLine = color(0x829D48, dark: 0x829D48)
    static let signIn = color(0x263D28, dark: 0xD6FB70)
    static let signInInk = color(0xFFFEF7, dark: 0x172013)

    /// `rgba(29, 36, 28, .08)`: the hairline under the header and beside day rules.
    static let hairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12) : UIColor(red: 29 / 255, green: 36 / 255, blue: 28 / 255, alpha: 0.08)
    })

    static let cardShadow = Color(red: 34 / 255, green: 38 / 255, blue: 32 / 255).opacity(0.11)
    static let bubbleShadow = Color(red: 45 / 255, green: 48 / 255, blue: 42 / 255).opacity(0.06)
    static let composerShadow = Color(red: 41 / 255, green: 44 / 255, blue: 38 / 255).opacity(0.09)

    /// Lora ships in the bundle (OFL); the serif falls back to New York if registration fails.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle) -> Font {
        if UIFont(name: "Lora-Regular", size: size) != nil {
            return Font.custom("Lora", size: size, relativeTo: style).weight(weight)
        }
        return Font.system(size: size, weight: weight, design: .serif)
    }

    static let wordmark = serif(20, weight: .semibold, relativeTo: .title3)
    static let display = serif(40, weight: .medium, relativeTo: .largeTitle)
    static let hero = serif(35, weight: .medium, relativeTo: .largeTitle)
    static let title = serif(30, weight: .medium, relativeTo: .title)
    static let heading = serif(24, weight: .medium, relativeTo: .title2)
    static let cardTitle = serif(18, weight: .semibold, relativeTo: .title3)
    static let rowTitle = serif(16, weight: .medium, relativeTo: .headline)
    static let quote = serif(25, relativeTo: .title)
    static let body = Font.custom("Inter", size: 17, relativeTo: .body)
    static let label = Font.custom("Inter", size: 14, relativeTo: .subheadline)
    static let labelStrong = Font.custom("Inter", size: 14, relativeTo: .subheadline).weight(.bold)
    static let detail = Font.custom("Inter", size: 13, relativeTo: .footnote)
    static let caption = Font.custom("Inter", size: 12, relativeTo: .caption)
    static let kicker = Font.custom("Inter", size: 12, relativeTo: .caption).weight(.bold)
    static let chip = Font.custom("JetBrainsMono-Regular", size: 12, relativeTo: .caption)

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

/// `JAPAN FAMILY TRIP`, `YOUR SHARED WORK`, `DECISION OPEN`: uppercase, letterspaced, bold.
struct OLSKicker: View {
    var text: String
    var color: Color = OLSTheme.eyebrow
    var tracking: CGFloat = 1.6

    var body: some View {
        Text(self.text.uppercased())
            .font(OLSTheme.kicker)
            .tracking(self.tracking)
            .foregroundStyle(self.color)
    }
}

/// The prototype's `.thread-project-object` / `.context-check-card` surface: white, 18pt
/// radius, faint border, soft drop shadow.
struct OLSCardSurface: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 18
    var fill: Color = OLSTheme.paper

    func body(content: Content) -> some View {
        content
            .padding(self.padding)
            .background(self.fill, in: RoundedRectangle(cornerRadius: self.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: self.radius, style: .continuous)
                    .strokeBorder(OLSTheme.hairline, lineWidth: 1)
            }
            .shadow(color: OLSTheme.cardShadow, radius: 15, y: 12)
    }
}

extension View {
    func olsCard(padding: CGFloat = 16, radius: CGFloat = 18, fill: Color = OLSTheme.paper) -> some View {
        self.modifier(OLSCardSurface(padding: padding, radius: radius, fill: fill))
    }
}
