import SwiftUI
import AuthenticationServices

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
    case sport
    case classic

    static var current: AppFontPreset {
        AppFontPreset(rawValue: UserDefaults.standard.string(forKey: "appFontPreset") ?? "") ?? .modern
    }

    var icon: String {
        switch self {
        case .modern:
            return "textformat"
        case .sport:
            return "figure.run"
        case .classic:
            return "book.closed"
        }
    }

    private var design: Font.Design {
        switch self {
        case .modern:
            return .default
        case .sport:
            return .rounded
        case .classic:
            return .serif
        }
    }

    func displayName(_ appLanguage: AppLanguage = .current) -> String {
        switch self {
        case .modern:
            return appLanguage.text("모던", "Modern")
        case .sport:
            return appLanguage.text("스포츠", "Sport")
        case .classic:
            return appLanguage.text("클래식", "Classic")
        }
    }

    func description(_ appLanguage: AppLanguage = .current) -> String {
        switch self {
        case .modern:
            return appLanguage.text("깔끔하고 선명한 기본형", "Clean and sharp everyday style")
        case .sport:
            return appLanguage.text("역동적인 둥근 러닝 스타일", "Energetic rounded running style")
        case .classic:
            return appLanguage.text("차분하고 또렷한 세리프 스타일", "Balanced serif style with character")
        }
    }

    func titleFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    func bodyFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

// MARK: - BeamChaser 디자인 시스템

enum RBColor {
    static let accent = Color.orange
    static let accentGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.55, blue: 0.0), Color(red: 1.0, green: 0.35, blue: 0.0)],
        startPoint: .leading, endPoint: .trailing
    )

    // 적응형 색상 — 라이트/다크 자동 전환
    static let bg = Color(light: Color(white: 0.96), dark: Color.black)
    static let cardBg = Color(light: Color.white, dark: Color(white: 0.11))
    static let cardBgLight = Color(light: Color(white: 0.95), dark: Color(white: 0.15))
    static let textPrimary = Color(light: Color(white: 0.1), dark: Color.white)
    static let textSecondary = Color(light: Color(white: 0.45), dark: Color(white: 0.65))
    static let textTertiary = Color(light: Color(white: 0.6), dark: Color(white: 0.45))
    static let divider = Color(light: Color(white: 0.88), dark: Color(white: 0.2))

    static let success = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let danger = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let laserRed = Color(red: 1.0, green: 0.15, blue: 0.15)
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
    static func hero(_ size: CGFloat) -> Font {
        AppFontPreset.current.titleFont(size: size, weight: .black)
    }
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .monospaced)
    }
    static func label(_ size: CGFloat) -> Font {
        AppFontPreset.current.bodyFont(size: size, weight: .semibold)
    }
    static func caption(_ size: CGFloat = 11) -> Font {
        AppFontPreset.current.bodyFont(size: size, weight: .medium)
    }
}

enum RBLayout {
    static let tabBarClearance: CGFloat = 104
    static let scrollBottomInset: CGFloat = 130
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
                    .font(RBFont.label(17))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RBColor.accentGradient)
            .clipShape(Capsule())
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
            .background(RBColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - 메트릭 박스

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
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textSecondary)
                .tracking(1.2)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(RBFont.metric(valueSize))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                if !unit.isEmpty {
                    Text(unit)
                        .font(RBFont.caption(12))
                        .foregroundStyle(unitColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
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
            .shadow(color: RBColor.laserRed.opacity(0.7), radius: glowRadius)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.4), lineWidth: 1.5)
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
        .background(color.opacity(0.15))
        .clipShape(Capsule())
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
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)

            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(RBFont.label(15))
            }
            .foregroundStyle(Color.black.opacity(0.88))
            .allowsHitTesting(false)

            SignInWithAppleButton(.signIn) { request in
                onRequest(request)
            } onCompletion: { result in
                onCompletion(result)
            }
            .signInWithAppleButtonStyle(.white)
            .opacity(0.015)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .disabled(isAuthenticating)
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
