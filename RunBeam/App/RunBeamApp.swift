import SwiftUI
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            print("GoogleService-Info.plist 없음 — Firebase 비활성 상태")
        }
        return true
    }
}

@main
struct RunBeamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var bleService = BLEService()
    @StateObject private var locationService = LocationService()
    @StateObject private var runSession = RunSessionManager()
    @StateObject private var profileService = ProfileService()
    @StateObject private var authService = AuthService()
    @StateObject private var backendService = BackendService()
    @StateObject private var phoneSession = PhoneSessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleService)
                .environmentObject(locationService)
                .environmentObject(runSession)
                .environmentObject(runSession.healthKit)
                .environmentObject(profileService)
                .environmentObject(authService)
                .environmentObject(backendService)
                .environmentObject(phoneSession)
                .onAppear {
                    // Watch 연동 서비스 주입
                    phoneSession.runSession      = runSession
                    phoneSession.bleService      = bleService
                    phoneSession.locationService = locationService
                }
                .onChange(of: runSession.runState) { _, state in
                    // 러닝 시작 시 Watch 동기화 타이머 가동
                    if state == .running {
                        phoneSession.startSync()
                    } else if state == .finished || state == .idle {
                        phoneSession.stopSync()
                    }
                }
        }
    }
}
