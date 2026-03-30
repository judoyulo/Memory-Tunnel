import SwiftUI

// MARK: - Design Tokens
// Single source of truth for Memory Tunnel's design system.
// All views read from here — never hardcode colors or spacing elsewhere.
// Sourced from DESIGN.md.

extension Color {
    // Backgrounds
    static let mtBackground = Color(hex: "#F5EAD8")   // warm cream
    static let mtSurface    = Color(hex: "#EDE0CC")   // slightly deeper for cards/notifs

    // Labels
    static let mtLabel      = Color(hex: "#1C1C1E")   // near-black
    static let mtSecondary  = Color(hex: "#636366")
    static let mtTertiary   = Color(hex: "#8E8E93")

    // Accent — PRECIOUS: use only at emotional peaks
    // ✓ Sent confirmation, birthday trigger dot, decay notification dot
    static let mtAccent     = Color(hex: "#C8956C")   // warm amber

    // Convenience initializer from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a,r,g,b) = (255, (int>>8)*17, (int>>4&0xF)*17, (int&0xF)*17)
        case 6: (a,r,g,b) = (255, int>>16, int>>8&0xFF, int&0xFF)
        case 8: (a,r,g,b) = (int>>24, int>>16&0xFF, int>>8&0xFF, int&0xFF)
        default:(a,r,g,b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius

enum Radius {
    static let none: CGFloat    = 0      // daily card, web preview
    static let micro: CGFloat   = 2      // chapter tiles
    static let button: CGFloat  = 8      // buttons
    static let card: CGFloat    = 12     // memory cards, notification strips
    static let full: CGFloat    = 9999   // avatar pills
}

// MARK: - Typography helpers

extension Font {
    // Display — hero headings (Daily Card sender name, Chapter title)
    static let mtDisplay = Font.system(size: 28, weight: .medium, design: .default)

    // Title — screen-level headings
    static let mtTitle   = Font.system(size: 20, weight: .semibold, design: .default)

    // Body — captions, descriptions
    static let mtBody    = Font.system(size: 15, weight: .regular, design: .default)

    // Label — UI labels, list item names, navigation
    static let mtLabel   = Font.system(size: 15, weight: .medium, design: .default)

    // Button — filled button labels (Primary, Accent, Destructive variants)
    static let mtButton  = Font.system(size: 17, weight: .semibold, design: .default)

    // Caption — metadata, timestamps, micro-copy
    static let mtCaption = Font.system(size: 12, weight: .regular, design: .default)

    // Data — tabular figures
    static let mtData    = Font.system(size: 13, weight: .regular, design: .monospaced)
}

// MARK: - Animation

extension Animation {
    /// Quick opacity change — photo fade-in, confirmation appear/disappear.
    static let mtFade   = Animation.easeOut(duration: 0.20)
    /// Slide-based step transitions — onboarding steps, Smart Start states.
    static let mtSlide  = Animation.easeOut(duration: 0.30)
    /// Photo reveal — cinematic darkroom-print entrance (scale 0.97→1 + fade).
    static let mtReveal = Animation.easeOut(duration: 0.45)
    /// Interactive spring — button press, card tap, face card appear.
    static let mtSpring = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// Confirmation bounce — amber checkmark, badge pop.
    static let mtBounce = Animation.spring(response: 0.40, dampingFraction: 0.60)
}

// MARK: - Spring Button Style

/// Applies a subtle spring scale effect on press — makes every tap feel responsive.
/// Usage: .buttonStyle(MTSpringButtonStyle())
struct MTSpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.mtSpring, value: configuration.isPressed)
    }
}
