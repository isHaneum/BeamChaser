import SwiftUI
import AuthenticationServices
import UIKit

// MARK: - 외관 모드 관리

enum AppearanceMode: String, CaseIterable {
    case system = "시스템"
    case light = "라이트"
    case dark = "다크"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    func displayName(_ appLanguage: AppLanguage = .current) -> String {
        let englishName: String
        switch self {
        case .system:
            englishName = "System"
        case .light:
            englishName = "Light"
        case .dark:
            englishName = "Dark"
        }

        return appLanguage.text(rawValue, englishName)
    }
}

// MARK: - 앱 언어 모드 관리

enum AppLanguage: String, CaseIterable {
    case system
    case korean
    case english

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    }

    var displayName: String {
        switch self {
        case .system: return AppLanguage.current.text("시스템", "System")
        case .korean: return AppLanguage.current.text("한국어", "Korean")
        case .english: return AppLanguage.current.text("영어", "English")
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            if Locale.preferredLanguages.first?.hasPrefix("en") == true {
                return Locale(identifier: "en")
            }
            return Locale(identifier: "ko_KR")
        case .korean:
            return Locale(identifier: "ko_KR")
        case .english:
            return Locale(identifier: "en")
        }
    }

    var isEnglish: Bool {
        locale.identifier.hasPrefix("en")
    }

    func text(_ korean: String, _ english: String) -> String {
        isEnglish ? english : korean
    }

    func localized(_ korean: String, table: String = "Localizable") -> String {
        guard isEnglish else { return korean }
        return Self.lookupLocalization(for: korean, localeIdentifier: "en", table: table) ?? korean
    }

    private static func lookupLocalization(for key: String, localeIdentifier: String, table: String) -> String? {
        guard
            let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return nil
        }

        let value = NSLocalizedString(key, tableName: table, bundle: bundle, value: key, comment: "")
        return value == key ? nil : value
    }
}

// MARK: - 앱 글꼴 프리셋

enum AppFontPreset: String, CaseIterable {
    case modern
    case rounded
    case sport
    case classic
    case editorial

    static var current: AppFontPreset {
        AppFontPreset(rawValue: UserDefaults.standard.string(forKey: "appFontPreset") ?? "") ?? .modern
    }

    var icon: String {
        switch self {
        case .modern:
            return "textformat.size"
        case .rounded:
            return "circle.grid.cross"
        case .sport:
            return "figure.run"
        case .classic:
            return "square.grid.2x2"
        case .editorial:
            return "textformat"
        }
    }

    func displayName(_ appLanguage: AppLanguage = .current) -> String {
        switch self {
        case .modern:
            return appLanguage.text("기본", "Default")
        case .rounded:
            return appLanguage.text("라운드", "Rounded")
        case .sport:
            return appLanguage.text("스포츠", "Sport")
        case .classic:
            return appLanguage.text("모던", "Modern")
        case .editorial:
            return appLanguage.text("에디토리얼", "Editorial")
        }
    }

    func description(_ appLanguage: AppLanguage = .current) -> String {
        switch self {
        case .modern:
            return appLanguage.text("SF Pro", "SF Pro")
        case .rounded:
            return appLanguage.text("SF Rounded", "SF Rounded")
        case .sport:
            return appLanguage.text("Condensed", "Condensed")
        case .classic:
            return appLanguage.text("Inter", "Inter")
        case .editorial:
            return appLanguage.text("Serif", "Serif")
        }
    }

    func titleFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch self {
        case .modern:
            return .system(size: size, weight: weight, design: .default)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .sport:
            return sportFont(size: size, weight: weight)
        case .classic:
            return customInterFont(size: size, weight: weight) ?? .system(size: size, weight: weight, design: .default)
        case .editorial:
            return .system(size: size, weight: weight, design: .serif)
        }
    }

    func bodyFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        switch self {
        case .modern:
            return .system(size: size, weight: weight, design: .default)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .sport:
            return .system(size: size, weight: weight, design: .default)
        case .classic:
            return customInterFont(size: size, weight: weight) ?? .system(size: size, weight: weight, design: .default)
        case .editorial:
            return .system(size: size, weight: weight, design: .serif)
        }
    }

    private func sportFont(size: CGFloat, weight: Font.Weight) -> Font {
        let condensedFont: UIFont
        if #available(iOS 17.0, *) {
            condensedFont = UIFont.systemFont(ofSize: size, weight: uiWeight(for: weight), width: .condensed)
        } else {
            condensedFont = UIFont.systemFont(ofSize: size, weight: uiWeight(for: weight))
        }

        return .custom(condensedFont.fontName, size: size)
    }

    private func uiWeight(for weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .black:
            return .black
        case .heavy:
            return .heavy
        case .bold:
            return .bold
        case .semibold:
            return .semibold
        case .medium:
            return .medium
        case .light:
            return .light
        case .thin, .ultraLight:
            return .thin
        default:
            return .regular
        }
    }

    private func customInterFont(size: CGFloat, weight: Font.Weight) -> Font? {
        let name: String
        switch weight {
        case .black:
            name = "Inter-Black"
        case .heavy:
            name = "Inter-ExtraBold"
        case .bold:
            name = "Inter-Bold"
        case .semibold:
            name = "Inter-SemiBold"
        case .medium:
            name = "Inter-Medium"
        case .light:
            name = "Inter-Light"
        case .thin, .ultraLight:
            name = "Inter-Thin"
        default:
            name = "Inter-Regular"
        }

        guard UIFont(name: name, size: size) != nil else {
            return nil
        }
        return .custom(name, size: size)
    }
}

enum AppColorTheme: String, CaseIterable {
    case beam
    case ember
    case sand
    case dusk

    static var current: AppColorTheme {
        AppColorTheme(rawValue: UserDefaults.standard.string(forKey: "appColorTheme") ?? "") ?? .beam
    }

    var icon: String {
        switch self {
        case .beam:
            return "circle.lefthalf.filled"
        case .ember:
            return "sun.max.fill"
        case .sand:
            return "sun.haze.fill"
        case .dusk:
            return "moon.stars.fill"
        }
    }

    func displayName(_ appLanguage: AppLanguage = .current) -> String {
        switch self {
        case .beam:
            return appLanguage.text("빔", "Beam")
        case .ember:
            return appLanguage.text("엠버", "Ember")
        case .sand:
            return appLanguage.text("샌드", "Sand")
        case .dusk:
            return appLanguage.text("더스크", "Dusk")
        }
    }

    var primary: Color {
        switch self {
        case .beam:
            return Color(red: 0.36, green: 0.45, blue: 0.96)
        case .ember:
            return Color(red: 0.98, green: 0.42, blue: 0.30)
        case .sand:
            return Color(red: 0.72, green: 0.56, blue: 0.18)
        case .dusk:
            return Color(red: 0.43, green: 0.36, blue: 0.85)
        }
    }

    var secondary: Color {
        switch self {
        case .beam:
            return Color(red: 0.50, green: 0.60, blue: 1.0)
        case .ember:
            return Color(red: 1.0, green: 0.58, blue: 0.48)
        case .sand:
            return Color(red: 0.85, green: 0.70, blue: 0.34)
        case .dusk:
            return Color(red: 0.61, green: 0.53, blue: 1.0)
        }
    }

    var gradientTail: Color {
        switch self {
        case .beam:
            return Color(red: 0.20, green: 0.29, blue: 0.72)
        case .ember:
            return Color(red: 0.76, green: 0.23, blue: 0.17)
        case .sand:
            return Color(red: 0.47, green: 0.33, blue: 0.10)
        case .dusk:
            return Color(red: 0.24, green: 0.18, blue: 0.56)
        }
    }

    var accentSurfaceLight: Color {
        switch self {
        case .beam:
            return Color(red: 0.92, green: 0.94, blue: 1.0)
        case .ember:
            return Color(red: 1.0, green: 0.94, blue: 0.92)
        case .sand:
            return Color(red: 0.97, green: 0.94, blue: 0.88)
        case .dusk:
            return Color(red: 0.94, green: 0.92, blue: 1.0)
        }
    }

    var accentSurfaceDark: Color {
        switch self {
        case .beam:
            return Color(red: 0.09, green: 0.12, blue: 0.26)
        case .ember:
            return Color(red: 0.21, green: 0.10, blue: 0.09)
        case .sand:
            return Color(red: 0.18, green: 0.14, blue: 0.08)
        case .dusk:
            return Color(red: 0.10, green: 0.08, blue: 0.22)
        }
    }
}

// MARK: - BeamChaser 디자인 시스템

enum RBColor {
    private static var theme: AppColorTheme { AppColorTheme.current }

    static var primary: Color { theme.primary }
    static var secondary: Color { theme.secondary }
    static var accent: Color { theme.primary }
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.primary,
                theme.gradientTail
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    static let onAccent = Color.white
    static var accentSurface: Color {
        Color(
            light: theme.accentSurfaceLight,
            dark: theme.accentSurfaceDark
        )
    }

    static let bg = Color(
        light: Color(red: 247.0 / 255.0, green: 247.0 / 255.0, blue: 244.0 / 255.0),
        dark: Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0)
    )
    static let bgElevated = Color(
        light: Color.white,
        dark: Color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0)
    )
    static let cardBg = Color(
        light: Color.white,
        dark: Color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0)
    )
    static let cardBgLight = Color(
        light: Color(red: 0.948, green: 0.948, blue: 0.930),
        dark: Color(red: 0.102, green: 0.102, blue: 0.102)
    )
    static let chrome = Color(
        light: Color.white.opacity(0.90),
        dark: Color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0).opacity(0.94)
    )
    static let textPrimary = Color(
        light: Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0),
        dark: Color.white
    )
    static let textSecondary = Color(
        light: Color(red: 102.0 / 255.0, green: 102.0 / 255.0, blue: 102.0 / 255.0),
        dark: Color(red: 184.0 / 255.0, green: 184.0 / 255.0, blue: 184.0 / 255.0)
    )
    static let textTertiary = Color(
        light: Color(red: 118.0 / 255.0, green: 118.0 / 255.0, blue: 118.0 / 255.0),
        dark: Color(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 142.0 / 255.0)
    )
    static let textDisabled = Color(
        light: Color(red: 0.660, green: 0.640, blue: 0.600),
        dark: Color(red: 0.400, green: 0.392, blue: 0.370)
    )
    static let divider = Color(
        light: Color(red: 229.0 / 255.0, green: 229.0 / 255.0, blue: 224.0 / 255.0),
        dark: Color(red: 42.0 / 255.0, green: 42.0 / 255.0, blue: 42.0 / 255.0)
    )
    static let overlay = Color(
        light: Color.black.opacity(0.055),
        dark: Color.white.opacity(0.090)
    )

    static let success = Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
    static let warning = Color(red: 0.92, green: 0.62, blue: 0.18)
    static let danger = Color(red: 1.0, green: 77.0 / 255.0, blue: 79.0 / 255.0)
    static let laserRed = danger
    static let paceFast = secondary
    static let paceSteady = success
    static let paceSlow = warning
}

enum RBRadius {
    static let chip: CGFloat = 12
    static let button: CGFloat = 14
    static let card: CGFloat = 16
    static let dock: CGFloat = 18
    static let cta: CGFloat = 16
}

enum RBSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum RBShadow {
    static let card = Color.black.opacity(0.08)
    static let floating = Color.black.opacity(0.18)
}

// MARK: - Color convenience init for light/dark

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

enum RBFont {
    static func display(_ size: CGFloat) -> Font {
        AppFontPreset.current.titleFont(size: size, weight: .black)
    }
    static func hero(_ size: CGFloat) -> Font {
        AppFontPreset.current.titleFont(size: size, weight: .black)
    }
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
    static func title(_ size: CGFloat) -> Font {
        AppFontPreset.current.titleFont(size: size, weight: .bold)
    }
    static func label(_ size: CGFloat) -> Font {
        AppFontPreset.current.bodyFont(size: size, weight: .semibold)
    }
    static func body(_ size: CGFloat) -> Font {
        AppFontPreset.current.bodyFont(size: size, weight: .medium)
    }
    static func caption(_ size: CGFloat = 11) -> Font {
        AppFontPreset.current.bodyFont(size: size, weight: .medium)
    }
    static func unit(_ size: CGFloat = 12) -> Font {
        AppFontPreset.current.bodyFont(size: size, weight: .regular)
    }
}

enum RBLayout {
    static let tabBarClearance: CGFloat = 104
    static let scrollBottomInset: CGFloat = 130
}

struct RunMetricBarItem: Identifiable, Hashable {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var id: String {
        [title, value, unit].joined(separator: "-")
    }
}

struct RunModeToggle: View {
    let titles: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: RunSurfaceToken.verticalSpacingSmall) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    onSelect(index)
                } label: {
                    Text(title)
                        .font(RBFont.label(16))
                        .foregroundStyle(selectedIndex == index ? Color.white : Color.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .frame(maxWidth: .infinity)
                        .frame(height: RunSurfaceToken.modeToggleHeight)
                        .background(
                            RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous)
                                .fill(selectedIndex == index ? RunSurfaceToken.primaryBlue.opacity(0.22) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous)
                                .stroke(selectedIndex == index ? RunSurfaceToken.primaryBlue.opacity(0.65) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous)
                .fill(RunSurfaceToken.glassBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
    }
}

struct RunMetricBar: View {
    let items: [RunMetricBarItem]
    let compact: Bool

    private var labelSize: CGFloat { compact ? 12 : 13 }
    private var valueSize: CGFloat { compact ? 20 : 22 }
    private var unitSize: CGFloat { compact ? 13 : 14 }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .center, spacing: 4) {
                    Text(item.title)
                        .font(AppFontPreset.current.bodyFont(size: labelSize, weight: .medium))
                        .foregroundStyle(RunSurfaceToken.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(item.value)
                            .font(.system(size: valueSize, weight: .bold, design: .rounded))
                            .foregroundStyle(item.tint)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)

                        if !item.unit.isEmpty {
                            Text(item.unit)
                                .font(AppFontPreset.current.bodyFont(size: unitSize, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.86))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .center)

                if index < items.count - 1 {
                    Divider()
                        .overlay(RunSurfaceToken.dividerColor)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 12 : 14)
        .frame(maxWidth: .infinity)
        .frame(height: RunSurfaceToken.metricBarHeight(compact: compact))
        .background(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .fill(RunSurfaceToken.darkPanelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
    }
}

struct RunPrimaryStats: View {
    let distance: String
    let time: String
    let pace: String
    let compact: Bool

    private var paceSize: CGFloat { compact ? 72 : 84 }
    private var paceUnitSize: CGFloat { compact ? 20 : 24 }
    private var distanceSize: CGFloat { compact ? 32 : 38 }
    private var distanceUnitSize: CGFloat { compact ? 13 : 15 }
    private var timeSize: CGFloat { compact ? 34 : 40 }

    var body: some View {
        VStack(spacing: compact ? 16 : 20) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(pace)
                    .font(.system(size: paceSize, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("/km")
                    .font(.system(size: paceUnitSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: ComponentTokens.RunSurface.verticalSpacingMedium) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(distance)
                        .font(.system(size: distanceSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("km")
                        .font(.system(size: distanceUnitSize, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity)

                Text(time)
                    .font(.system(size: timeSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct RunMapSummaryBar: View {
    struct Item: Identifiable {
        let title: String
        let value: String
        let unit: String

        var id: String {
            [title, value, unit].joined(separator: "-")
        }
    }

    let items: [Item]
    let compact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 3) {
                    Text(item.title)
                        .font(RBFont.caption(10))
                        .foregroundStyle(RunSurfaceToken.secondaryText)
                        .lineLimit(1)

                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(item.value)
                            .font(RBFont.metric(compact ? 17 : 18))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        if !item.unit.isEmpty {
                            Text(item.unit)
                                .font(RBFont.unit(11))
                                .foregroundStyle(Color.white.opacity(0.76))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Divider()
                        .overlay(RunSurfaceToken.dividerColor)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: RunSurfaceToken.mapSummaryHeight(compact: compact))
        .background(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .fill(RunSurfaceToken.glassBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
    }
}

private struct RunSurfaceActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let icon: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))

                Text(title)
                    .font(RBFont.label(16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: RunSurfaceToken.runningControlHeight)
            .background(backgroundStyle)
            .overlay(
                RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        switch style {
        case .primary:
            return AnyShapeStyle(RBColor.accentGradient)
        case .secondary:
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
    }

    private var strokeColor: Color {
        switch style {
        case .primary:
            return Color.white.opacity(0.18)
        case .secondary:
            return RunSurfaceToken.dividerColor
        }
    }
}

struct PausedBottomPanel: View {
    let message: String
    let finishTitle: String
    let resumeTitle: String
    let onFinish: () -> Void
    let onResume: () -> Void
    let compact: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text(message)
                .font(RBFont.body(14))
                .foregroundStyle(RunSurfaceToken.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: RunSurfaceToken.verticalSpacingMedium) {
                RunSurfaceActionButton(
                    title: finishTitle,
                    icon: "stop.fill",
                    style: .secondary,
                    action: onFinish
                )

                RunSurfaceActionButton(
                    title: resumeTitle,
                    icon: "play.fill",
                    style: .primary,
                    action: onResume
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, compact ? 18 : 20)
        .padding(.bottom, compact ? 18 : 20)
        .frame(maxWidth: .infinity)
        .frame(minHeight: RunSurfaceToken.pausedPanelHeight(compact: compact))
        .background(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .fill(RunSurfaceToken.darkPanelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
    }
}

// MARK: - 공통 버튼 스타일

struct RBPrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                }
                Text(title)
                    .font(RBFont.label(16))
            }
            .foregroundStyle(RBColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RBColor.accentGradient)
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
            .shadow(color: RBColor.primary.opacity(0.22), radius: 14, y: 6)
        }
    }
}

// MARK: - 공통 카드

struct RBCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                    .fill(RBColor.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                    .stroke(RBColor.divider.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: RBShadow.card, radius: 18, y: 10)
    }
}

// MARK: - 바형 토글

struct RBBarToggleLabel: View {
    let title: String?
    let isOn: Bool
    var tint: Color = RBColor.accent
    var height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            if let title {
                Text(title)
                    .font(RBFont.label(12))
                    .foregroundStyle(isOn ? RBColor.onAccent : RBColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)

            Text(isOn ? "ON" : "OFF")
                .font(RBFont.caption(10))
                .foregroundStyle(isOn ? RBColor.onAccent : RBColor.textTertiary)

            Circle()
                .fill(isOn ? RBColor.onAccent : RBColor.textTertiary.opacity(0.72))
                .frame(width: 9, height: 9)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: min(RBRadius.chip, height / 2), style: .continuous)
                .fill(isOn ? tint : RBColor.cardBgLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: min(RBRadius.chip, height / 2), style: .continuous)
                .stroke(isOn ? Color.white.opacity(0.20) : RBColor.divider.opacity(0.85), lineWidth: 1)
        )
    }
}

struct RBBarToggle: View {
    let title: String?
    @Binding var isOn: Bool
    var tint: Color = RBColor.accent
    var height: CGFloat = 34
    var onChange: ((Bool) -> Void)?

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                isOn.toggle()
                onChange?(isOn)
            }
        } label: {
            RBBarToggleLabel(title: title, isOn: isOn, tint: tint, height: height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? "Toggle")
        .accessibilityValue(isOn ? "ON" : "OFF")
    }
}

// MARK: - 메트릭 박스

struct RBMetricLine: View {
    let value: String
    let unit: String
    var valueFont: Font
    var unitFont: Font = RBFont.unit(13)
    var valueColor: Color = RBColor.textPrimary
    var unitColor: Color = RBColor.textSecondary
    var spacing: CGFloat = 4
    var alignment: Alignment = .center

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: spacing) {
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)

            if !unit.isEmpty {
                Text(unit)
                    .font(unitFont)
                    .foregroundStyle(unitColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .allowsTightening(true)
        .frame(maxWidth: .infinity, alignment: alignment)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MetricView: View {
    let label: String
    let value: String
    let unit: String
    var valueSize: CGFloat = 36
    var alignment: HorizontalAlignment = .center
    var valueColor: Color = RBColor.textPrimary
    var unitColor: Color = RBColor.textSecondary

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textSecondary)
                .tracking(1)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(valueSize),
                unitFont: RBFont.unit(12),
                valueColor: valueColor,
                unitColor: unitColor,
                spacing: 3,
                alignment: metricAlignment
            )
        }
    }

    private var metricAlignment: Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        default:
            return .center
        }
    }
}

// MARK: - 글로우 도트 (레이저 마커)

struct LaserDot: View {
    var size: CGFloat = 16
    var glowRadius: CGFloat = 10

    var body: some View {
        Circle()
            .fill(RBColor.laserRed)
            .frame(width: size, height: size)
            .shadow(color: RBColor.laserRed.opacity(0.22), radius: glowRadius * 0.45)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
    }
}

// MARK: - 상태 배지

struct StatusBadge: View {
    let text: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(RBFont.label(12))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous)
                .stroke(color.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))
    }
}

// MARK: - 브랜드 로그인 버튼

struct GoogleBrandIcon: View {
    var size: CGFloat = 20

    var body: some View {
        let lineWidth = max(3.0, size * 0.22)
        let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
        let red = Color(red: 0.91, green: 0.3, blue: 0.24)
        let yellow = Color(red: 0.98, green: 0.74, blue: 0.19)
        let green = Color(red: 0.2, green: 0.74, blue: 0.34)

        return ZStack {
            Circle()
                .trim(from: 0.02, to: 0.23)
                .stroke(blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-10))

            Circle()
                .trim(from: 0.23, to: 0.49)
                .stroke(red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-10))

            Circle()
                .trim(from: 0.49, to: 0.71)
                .stroke(yellow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-10))

            Circle()
                .trim(from: 0.71, to: 0.98)
                .stroke(green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-10))

            Circle()
                .fill(Color.white)
                .frame(width: size * 0.52, height: size * 0.52)

            Rectangle()
                .fill(Color.white)
                .frame(width: size * 0.30, height: size * 0.22)
                .offset(x: size * 0.18)

            RoundedRectangle(cornerRadius: lineWidth / 2, style: .continuous)
                .fill(blue)
                .frame(width: size * 0.30, height: lineWidth)
                .offset(x: size * 0.15)
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }
}

struct LocalizedAppleSignInButton: View {
    let title: String
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 14
    var isAuthenticating: Bool = false
    var isAvailable: Bool = true
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isAvailable ? 1 : 0.76))

            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(RBFont.label(15))
            }
            .foregroundStyle(Color.black.opacity(isAvailable ? 0.88 : 0.45))
            .allowsHitTesting(false)

            if isAvailable {
                SignInWithAppleButton(.signIn) { request in
                    onRequest(request)
                } onCompletion: { result in
                    onCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .opacity(0.015)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .opacity(isAvailable ? 1 : 0.78)
        .disabled(isAuthenticating || !isAvailable)
    }
}

struct GoogleBrandedSignInButton: View {
    let title: String
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 14
    var isAuthenticating: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleBrandIcon(size: 20)
                Text(title)
                    .font(RBFont.label(15))
            }
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .disabled(isAuthenticating)
    }
}
