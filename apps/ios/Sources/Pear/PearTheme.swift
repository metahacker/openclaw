import SwiftUI
import UIKit

/// PEAR Playground design tokens — the prototype's shared.css translated to native.
/// Light = the cream world, dark = the espresso world; both resolve automatically
/// through dynamic UIColors so every surface follows the system appearance.
enum PearTheme {
    /// Page ground (`--cream`).
    static let cream = dynamicColor(light: 0xFAF6EF, dark: 0x181410)
    /// Card surface (`--paper`).
    static let paper = dynamicColor(light: 0xFFFFFF, dark: 0x221D17)
    /// Primary text (`--ink`).
    static let ink = dynamicColor(light: 0x29241D, dark: 0xEDE5D6)
    /// Secondary text (`--walnut`).
    static let walnut = dynamicColor(light: 0x6E6152, dark: 0xB5A68F)
    /// Tertiary/metadata text (`--faint`).
    static let faint = dynamicColor(light: 0x9A8D7B, dark: 0x7E7260)
    /// Hairline borders (`--line`).
    static let line = dynamicColor(light: 0xE7DFD2, dark: 0x342D24)
    /// Emoji glyph tiles (`--tile`).
    static let tile = dynamicColor(light: 0xF2EBDD, dark: 0x2C261E)
    /// Brand green (`--pear`), brightened in the dark world for contrast.
    static let pear = dynamicColor(light: 0x56742F, dark: 0xA3C46A)
    /// Soft green chip background (`--pear-soft`).
    static let pearSoft = dynamicColor(light: 0xEDF3E2, dark: 0x2A331E)
    /// "Waiting on you" amber (`--amber`).
    static let amber = dynamicColor(light: 0xB8860B, dark: 0xD9A83F)
    /// Your outgoing chat bubble.
    static let youBubble = dynamicColor(light: 0xDFE9CB, dark: 0x39442A)
    /// PEAR's incoming chat bubble (white / dark paper).
    static let pearBubble = dynamicColor(light: 0xFFFFFF, dark: 0x262019)
    /// Presence/health dot green.
    static let presence = dynamicColor(light: 0x6FA24C, dark: 0x7FB553)

    // MARK: - Type ramp (native equivalents: New York serif, SF body, SF Mono truth-lines)

    /// Page titles — "What we're working on".
    static let pageTitle = Font.system(size: 30, weight: .semibold, design: .serif)
    /// Card titles.
    static let cardTitle = Font.system(size: 17, weight: .medium, design: .serif)
    /// Smaller serif titles (thread rows, page rows).
    static let rowTitle = Font.system(size: 15.5, weight: .medium, design: .serif)
    /// One-line summaries.
    static let summary = Font.system(size: 14)
    /// Hashtag chips.
    static let chip = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// Uppercase kind tags / day markers.
    static let kind = Font.system(size: 11, design: .monospaced)
    /// The truth line under the Field.
    static let truthLine = Font.system(size: 11, design: .monospaced)

    private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1)
    }
}

// MARK: - Shared atoms

/// The softly glowing presence dot — alive, not blinking.
struct PearPresenceDot: View {
    var size: CGFloat = 7
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(PearTheme.presence)
            .frame(width: self.size, height: self.size)
            .shadow(color: PearTheme.presence.opacity(self.glowing ? 0.9 : 0.35), radius: self.glowing ? 6 : 2)
            .scaleEffect(self.glowing ? 1.08 : 0.94)
            .onAppear {
                guard !self.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    self.glowing = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// A `#hashtag` chip in prototype grammar.
struct PearTagChip: View {
    let tag: String

    var body: some View {
        Text(self.tag.hasPrefix("#") ? self.tag : "#\(self.tag)")
            .font(PearTheme.chip)
            .foregroundStyle(PearTheme.pear)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(PearTheme.pearSoft, in: Capsule())
            .lineLimit(1)
    }
}

/// Uppercase mono kind tag ("report", "slack · today").
struct PearKindTag: View {
    let text: String

    var body: some View {
        Text(self.text.uppercased())
            .font(PearTheme.kind)
            .kerning(1.1)
            .foregroundStyle(PearTheme.faint)
            .lineLimit(1)
    }
}

/// Emoji glyph on a warm tile, prototype `.glyph`.
struct PearGlyphTile: View {
    let emoji: String
    var side: CGFloat = 46

    var body: some View {
        Text(self.emoji)
            .font(.system(size: self.side * 0.48))
            .frame(width: self.side, height: self.side)
            .background(PearTheme.tile, in: RoundedRectangle(cornerRadius: self.side * 0.24, style: .continuous))
    }
}

/// Day separator: mono uppercase label with a hairline running out.
struct PearDayMark: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Text(self.label.uppercased())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .kerning(1.6)
                .foregroundStyle(PearTheme.walnut)
            Rectangle()
                .fill(PearTheme.line)
                .frame(height: 1)
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
    }
}

/// Standard card chrome: paper surface, hairline, gentle radius.
struct PearCardBackground: ViewModifier {
    var accented: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PearTheme.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(PearTheme.line, lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        if self.accented {
                            // Prototype chatcards carry a pear-green left seam.
                            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                                .fill(PearTheme.pear)
                                .frame(width: 3)
                        }
                    }
            }
    }
}

extension View {
    func pearCard(accented: Bool = false) -> some View {
        self.modifier(PearCardBackground(accented: accented))
    }
}
