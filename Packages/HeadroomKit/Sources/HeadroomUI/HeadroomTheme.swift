import HeadroomModel
import SwiftUI

/// Headroom's always-dark palette (spec §1.1, §1.2). The pill and panel never follow the system
/// appearance.
public enum HeadroomTheme {
    public static let pillBackground = Color(hex: 0x000000)
    public static let panelBackground = Color(hex: 0x111111)
    public static let track = Color(hex: 0x444441)

    public static let primaryText = Color(hex: 0xF1EFE8)
    public static let secondaryText = Color(hex: 0x888780)
    public static let separator = Color(hex: 0xF1EFE8, opacity: 0.08)
    public static let rowHighlight = Color(hex: 0xF1EFE8, opacity: 0.06)
    public static let buttonFill = Color(hex: 0xF1EFE8, opacity: 0.12)

    public static let normal = Color(hex: 0xF1EFE8)
    public static let warning = Color(hex: 0xEF9F27)
    public static let critical = Color(hex: 0xE24B4A)

    static let workingHex: UInt32 = 0x5DCAA5
    public static let working = Color(hex: workingHex)
    /// `working` for Core Animation (the live pulse ring).
    static var workingCGColor: CGColor { CGColor.sRGB(hex: workingHex) }
    public static let waiting = Color(hex: 0xEF9F27)
    public static let idle = Color(hex: 0x5F5E5A)

    /// The rings are drawn at this opacity when the data is stale (spec §1.1). Numbers stay at
    /// full opacity: amber or red text at 45 % on black falls below 3:1 contrast.
    public static let staleOpacity = 0.45

    public static func color(for severity: Severity) -> Color {
        switch severity {
        case .normal: normal
        case .warning: warning
        case .critical: critical
        }
    }

    public static func color(for dot: DotState) -> Color {
        switch dot {
        case .working: working
        case .waiting: waiting
        case .idle: idle
        }
    }

    public static func color(for tone: MomentDisplay.Tone) -> Color {
        switch tone {
        case .finished: working
        case .needsInput: waiting
        case .limit(let severity): color(for: severity)
        }
    }
}

extension Color {
    /// An sRGB color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension CGColor {
    /// An sRGB color from a 0xRRGGBB literal.
    static func sRGB(hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
