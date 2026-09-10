import SwiftUI
import UIKit

/// The Sep 4 One Living Surface palette. PEAR's supplied design intentionally
/// overrides upstream OpenClaw typography; scale it with the person's text size.
enum OLSTheme {
    static let background = color(0xF6F2EA, dark: 0x191C17)
    static let paper = color(0xFFFFFF, dark: 0x252A22)
    static let ink = color(0x252A23, dark: 0xF5F3EA)
    static let secondary = color(0x65705F, dark: 0xBCC4B4)
    static let line = color(0xDADDD3, dark: 0x40473A)
    static let accent = color(0x526B3D, dark: 0xDFF587)
    static let human = color(0xDFF587, dark: 0x3D492A)
    static let soft = color(0xEBEEDC, dark: 0x30392A)
    static let warning = color(0x88622A, dark: 0xE9BD72)
    static let body = Font.custom("Inter", size: 17, relativeTo: .body)
    static let title = Font.custom("Georgia", size: 30, relativeTo: .title)
    static let heading = Font.custom("Georgia", size: 21, relativeTo: .title3)
    static let label = Font.custom("Inter", size: 15, relativeTo: .subheadline)
    static let caption = Font.custom("Inter", size: 12, relativeTo: .caption)
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

struct OLSCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22).strokeBorder(OLSTheme.line, lineWidth: 1)
            }
    }
}

extension View {
    func olsCard() -> some View {
        self.modifier(OLSCardSurface())
    }
}
