import SwiftUI

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
}

// MARK: - 앱 언어 모드 관리

enum AppLanguage: String, CaseIterable {
    case system
    case korean
    case english

    var displayName: String {
        switch self {
        case .system: return "시스템"
        case .korean: return "한국어"
        case .english: return "English"
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
}

// MARK: - 런빔 디자인 시스템

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
        .system(size: size, weight: .black, design: .rounded)
    }
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .monospaced)
    }
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
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

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textSecondary)
                .tracking(1.2)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(RBFont.metric(valueSize))
                    .foregroundStyle(RBColor.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
                if !unit.isEmpty {
                    Text(unit)
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
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
