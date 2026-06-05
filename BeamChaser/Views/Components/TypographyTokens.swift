import SwiftUI

enum TypographyTokens {
    static let displayPace = Font.system(size: 72, weight: .heavy, design: .monospaced)
    static let displayTime = Font.system(size: 48, weight: .bold, design: .monospaced)
    static let displayDistance = Font.system(size: 40, weight: .bold, design: .monospaced)
    static let metricValue = Font.system(size: 22, weight: .bold, design: .monospaced)
    static let label = AppFontPreset.current.bodyFont(size: 13, weight: .medium)
    static let buttonText = AppFontPreset.current.bodyFont(size: 18, weight: .bold)

    static func currentPaceSize(compact: Bool) -> CGFloat {
        compact ? 68 : 76
    }

    static func secondaryRunValueSize(compact: Bool, kind: SecondaryRunMetricKind) -> CGFloat {
        switch kind {
        case .time:
            return compact ? 48 : 56
        case .distance:
            return compact ? 44 : 52
        }
    }

    static func unitSize(compact: Bool, emphasis: UnitEmphasis = .regular) -> CGFloat {
        switch emphasis {
        case .hero:
            return compact ? 22 : 26
        case .regular:
            return compact ? 12 : 13
        }
    }
}

enum SecondaryRunMetricKind {
    case time
    case distance
}

enum UnitEmphasis {
    case hero
    case regular
}
