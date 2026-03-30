import SwiftUI
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            print("⚠️ GoogleService-Info.plist 없음 — Firebase 비활성 상태")
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
        }
    }
}
