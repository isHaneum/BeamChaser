import SwiftUI

struct GameSelectView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 게임 모드 소개
                    VStack(spacing: 8) {
                        Image(systemName: "laser.burst")
                            .font(.system(size: 28))
                            .foregroundStyle(RBColor.accent)
                        Text(appLanguage.localized("레이저로 즐기는 러닝 게임"))
                            .font(RBFont.label(15))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(appLanguage.localized("BeamChaser의 레이저를 활용해 다양한 게임 모드로\n더 재미있게 달려보세요!"))
                            .font(RBFont.caption(12))
                            .foregroundStyle(RBColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 12)

                    ForEach(GameType.allCases, id: \.self) { game in
                        NavigationLink(destination: GamePlaceholderView(game: game)) {
                            gameCard(game)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(appLanguage.localized("게임 모드"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func gameCard(_ game: GameType) -> some View {
        HStack(spacing: 14) {
            Image(systemName: game.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(gameColor(game))
                .frame(width: 52, height: 52)
                .background(gameColor(game).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(game.rawValue)
                        .font(RBFont.label(16))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(appLanguage.localized("준비 중"))
                        .font(RBFont.caption(9))
                        .foregroundStyle(RBColor.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RBColor.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(gameDescription(game))
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RBColor.textTertiary)
        }
        .padding(14)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func gameColor(_ game: GameType) -> Color {
        switch game {
        case .heartRun: return RBColor.danger
        case .appleRun: return RBColor.success
        case .hiFive: return Color.yellow
        case .roadRun: return Color.blue
        }
    }

    private func gameDescription(_ game: GameType) -> String {
        switch game {
        case .heartRun: return appLanguage.localized("하트 모양 경로를 따라 달리며 레이저로 하트를 그려보세요")
        case .appleRun: return appLanguage.localized("지도 위 사과를 수집하며 달리는 수집형 러닝")
        case .hiFive: return appLanguage.localized("다른 러너와 만나면 하이파이브! 소셜 러닝 게임")
        case .roadRun: return appLanguage.localized("지도 땅따먹기! 달린 도로를 점령하세요")
        }
    }
}

struct GamePlaceholderView: View {
    let game: GameType
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: game.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(RBColor.textTertiary)

                Text(game.rawValue)
                    .font(RBFont.hero(24))
                    .foregroundStyle(RBColor.textPrimary)

                Text(appLanguage.localized("준비 중입니다"))
                    .font(RBFont.label(15))
                    .foregroundStyle(RBColor.textSecondary)

                Text(appLanguage.localized("이 게임 모드는 향후 업데이트에서 제공될 예정입니다."))
                    .font(RBFont.caption(13))
                    .foregroundStyle(RBColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle(game.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GameSelectView()
    }
}
