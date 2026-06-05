import SwiftUI

enum ColorTokens {
    static let primary = RBColor.primary
    static let background = RBColor.bg
    static let surface = RBColor.cardBg
    static let surfaceDim = RBColor.cardBgLight
    static let textPrimary = RBColor.textPrimary
    static let textSecondary = RBColor.textSecondary
    static let warning = RBColor.warning
    static let danger = RBColor.danger
    static let success = RBColor.success

    enum Run {
        static let backdropStart = Color(red: 0.05, green: 0.06, blue: 0.09)
        static let backdropEnd = Color(red: 0.10, green: 0.12, blue: 0.18)
        static let chrome = Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.92)
        static let panel = Color.black.opacity(0.84)
        static let glass = Color.black.opacity(0.72)
        static let divider = Color.white.opacity(0.14)
        static let secondaryText = Color.white.opacity(0.65)
        static let paceForeground = Color.white
        static let paceSecondary = Color.white.opacity(0.82)
        static let climateStable = RBColor.success
        static let climateCaution = RBColor.warning
        static let climateRisk = RBColor.danger
    }

    enum Split {
        static let cardBackground = Color(red: 0.965, green: 0.965, blue: 0.955)
        static let stroke = Color.black.opacity(0.06)
        static let primaryText = Color.black.opacity(0.90)
        static let secondaryText = Color.black.opacity(0.68)
        static let tertiaryText = Color.black.opacity(0.56)
        static let mutedFill = Color.black.opacity(0.075)
    }

    enum Share {
        static let primary = Color(red: 0.36, green: 0.45, blue: 0.96)
        static let primaryDeep = Color(red: 0.20, green: 0.29, blue: 0.72)
        static let primaryMist = Color(red: 0.93, green: 0.95, blue: 1.0)
        static let background = Color.white
    }
}
