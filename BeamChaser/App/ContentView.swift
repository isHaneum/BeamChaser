import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("appFontPreset") private var appFontPresetRaw: String = AppFontPreset.modern.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var healthKit: HealthKitService
    @EnvironmentObject private var runSession: RunSessionManager

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    enum Tab: CaseIterable {
        case home, history, community, profile
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ZStack {
                tabPage(HomeView(), for: .home)
                tabPage(RunHistoryView(), for: .history)
                tabPage(CommunityView(), for: .community)
                tabPage(ProfileView(), for: .profile)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if shouldShowTabBar {
                    customTabBar
                }
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .environment(\.locale, appLanguage.locale)
        .onChange(of: appFontPresetRaw) { _, _ in
            // AppStorage changes trigger a root refresh so RBFont picks up the selected preset immediately.
        }
        // 최초 실행 시에만 온보딩 풀스크린 표시
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
                .environmentObject(locationService)
                .environmentObject(healthKit)
        }
    }

    private func tabPage<Content: View>(_ content: Content, for tab: Tab) -> some View {
        content
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }

    private var shouldShowTabBar: Bool {
        runSession.runState == .idle && runSession.currentRecord == nil
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RBColor.divider.opacity(0.65))
                .frame(height: 1)

            HStack(spacing: 8) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        guard selectedTab != tab else { return }
                        withAnimation(.easeOut(duration: 0.14)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tabIcon(tab))
                                .font(.system(size: 18, weight: .semibold))
                            Text(tabTitle(tab))
                                .font(RBFont.caption(11))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : RBColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(selectedTab == tab ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(.clear))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(selectedTab == tab ? Color.white.opacity(0.10) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(RBColor.bg.opacity(0.98).ignoresSafeArea())
    }

    private func tabTitle(_ tab: Tab) -> String {
        switch tab {
        case .home:
            return appLanguage.text("홈", "Home")
        case .history:
            return appLanguage.text("기록", "History")
        case .community:
            return appLanguage.text("커뮤니티", "Community")
        case .profile:
            return appLanguage.text("프로필", "Profile")
        }
    }

    private func tabIcon(_ tab: Tab) -> String {
        switch tab {
        case .home:
            return "house.fill"
        case .history:
            return "clock.arrow.circlepath"
        case .community:
            return "person.2.fill"
        case .profile:
            return "person.fill"
        }
    }
}
