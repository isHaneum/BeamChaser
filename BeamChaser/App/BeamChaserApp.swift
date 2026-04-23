import SwiftUI
import FirebaseCore
import FirebaseAuth
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            if
                let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                let config = NSDictionary(contentsOfFile: path),
                let configuredBundleID = config["BUNDLE_ID"] as? String,
                let runningBundleID = Bundle.main.bundleIdentifier,
                configuredBundleID != runningBundleID
            {
                print("GoogleService-Info.plist 번들 ID 불일치: \(configuredBundleID) != \(runningBundleID)")
            }
        } else {
            print("GoogleService-Info.plist 없음 — Firebase 비활성 상태")
        }
        return true
    }

    #if canImport(GoogleSignIn)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
    #endif
}

@main
struct BeamChaserApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // MARK: - State Objects (Dependency Injection)

    @StateObject private var bleService: BLEService = {
        #if targetEnvironment(simulator)
        return MockBLEService()
        #else
        // 실제 기기에서도 강제로 Mock 모드를 쓰고 싶다면 이 부분을 수정 가능
        return ActualBLEService()
        #endif
    }()

    @StateObject private var locationService = LocationService()
    @StateObject private var runSession = RunSessionManager()
    @StateObject private var profileService = ProfileService()
    @StateObject private var authService = AuthService()
    @StateObject private var backendService = BackendService()
    @StateObject private var nowPlayingService = NowPlayingService()
    @StateObject private var phoneSession = PhoneSessionManager()
    @StateObject private var voiceGuide = VoiceGuideService()
    @State private var didHydrateRemoteRunHistory = false

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
                .environmentObject(nowPlayingService)
                .environmentObject(phoneSession)
                .environmentObject(voiceGuide)
                .onAppear {
                    // 서비스 간 의존성 주입
                    runSession.bleService = bleService
                    runSession.locationService = locationService
                    runSession.healthKit.refreshAuthorizationStatus()
                    nowPlayingService.activate()
                    syncRunnerProgress()
                    
                    // Watch 연동 서비스 주입
                    phoneSession.runSession      = runSession
                    phoneSession.bleService      = bleService
                    phoneSession.locationService = locationService

                    if bleService.isConnected {
                        locationService.startTrackingForBLETelemetryIfNeeded()
                        runSession.startPhoneTelemetry()
                    }
                }
                .onChange(of: bleService.isConnected) { _, isConnected in
                    if isConnected {
                        locationService.startTrackingForBLETelemetryIfNeeded()
                        runSession.startPhoneTelemetry()
                    } else {
                        runSession.stopPhoneTelemetry()
                        if runSession.runState == .idle || runSession.runState == .finished {
                            locationService.stopTracking()
                        }
                    }
                }
                .onReceive(runSession.$savedRecords.dropFirst()) { _ in
                    syncRunnerProgress()
                }
                .onChange(of: runSession.healthKit.currentHeartRate) { _, bpm in
                    phoneSession.updateHeartRate(Int(bpm.rounded()))
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

    private func syncRunnerProgress() {
        profileService.evaluateAfterRun(records: runSession.savedRecords)

        Task { @MainActor in
            guard FirebaseApp.app() != nil, let authUser = Auth.auth().currentUser else { return }

            let displayName = profileService.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (authService.userName ?? "러너")
                : profileService.nickname

            if backendService.currentUser == nil {
                await backendService.loadOrCreateUser(authUser: authUser, displayName: displayName)
            }

            await hydrateRemoteRunHistoryIfNeeded()

            let validRecords = runSession.savedRecords.filter { $0.totalDistanceMeters > 100 }
            let totalDistanceKm = validRecords.reduce(0.0) { $0 + $1.totalDistanceMeters / 1000.0 }
            let totalTimeSeconds = validRecords.reduce(0.0) { $0 + $1.elapsedSeconds }

            await backendService.updateUserProfile([
                "displayName": displayName,
                "level": profileService.level.rawValue,
                "totalDistanceKm": totalDistanceKm,
                "totalRuns": validRecords.count,
                "totalTimeSeconds": totalTimeSeconds,
            ])

            await backendService.syncRunRecords(validRecords)
            await backendService.syncChallengeProgress(
                records: validRecords,
                monthlyGoal: profileService.monthlyGoal
            )
            await backendService.loadCurrentChallengeProgress(monthlyGoal: profileService.monthlyGoal)
        }
    }

    @MainActor
    private func hydrateRemoteRunHistoryIfNeeded() async {
        guard !didHydrateRemoteRunHistory else { return }
        didHydrateRemoteRunHistory = true

        do {
            let remoteRecords = try await backendService.fetchRunHistory(limit: 200)
                .compactMap { $0.toRunRecord() }
            runSession.mergeRemoteRecords(remoteRecords)
        } catch {
            didHydrateRemoteRunHistory = false
        }
    }
}
