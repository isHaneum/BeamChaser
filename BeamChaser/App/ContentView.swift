import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    enum Tab {
        case home, history, community, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("홈", systemImage: "house.fill")
                }
                .tag(Tab.home)

            RunHistoryView()
                .tabItem {
                    Label("기록", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.history)

            CommunityView()
                .tabItem {
                    Label("커뮤니티", systemImage: "person.2.fill")
                }
                .tag(Tab.community)

            ProfileView()
                .tabItem {
                    Label("프로필", systemImage: "person.fill")
                }
                .tag(Tab.profile)
        }
        .tint(RBColor.accent)
        .preferredColorScheme(appearanceMode.colorScheme)
    }
}
