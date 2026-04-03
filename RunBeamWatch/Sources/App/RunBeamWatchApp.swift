import SwiftUI

@main
struct RunBeamWatchApp: App {
    @StateObject private var watchSession = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(watchSession)
        }
    }
}

/// 러닝 상태에 따라 진입점 분기
struct RootView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        if session.isRunning || session.isPaused {
            RunningTabView()
        } else {
            IdleView()
        }
    }
}

/// 러닝 중 3탭 구조
/// Tab 1: RunDashboardView  (메인 게이지)
/// Tab 2: HardwareControlView (서보 제어)
/// Tab 3: PauseFinishView  (일시정지/종료)
struct RunningTabView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        TabView {
            RunDashboardView()
            HardwareControlView()
            PauseFinishView()
        }
        .tabViewStyle(.page)
    }
}
