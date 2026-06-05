import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import Security
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import UIKit

enum AuthSignInProvider: String {
    case apple
    case google
}

/// Apple / Google 로그인 인증 서비스
@MainActor
final class AuthService: ObservableObject {

    @Published var isSignedIn = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var selectedProvider: AuthSignInProvider?
    @Published var userName: String?
    @Published var userEmail: String?
    @Published var userIdentifier: String?
    @Published var signInError: String?

    private let authUserDefaultsKey = "auth_user_id"
    private let appleUserDefaultsKey = "apple_user_id"
    private let authProviderDefaultsKey = "auth_provider"
    private var currentNonce: String?
    private var firebaseAuthHandle: AuthStateDidChangeListenerHandle?
    weak var bleService: BLEService?

    var isGoogleSignInAvailable: Bool {
        #if canImport(GoogleSignIn)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }

    var isAppleSignInAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    var appleSignInAvailabilityMessage: String? {
        guard !isAppleSignInAvailable else { return nil }
        return AppLanguage.current.text(
            "시뮬레이터에서는 Apple 로그인을 사용할 수 없습니다. 실제 iPhone에서 테스트해주세요.",
            "Apple sign-in isn't available in the simulator. Test on a physical iPhone."
        )
    }

    init() {
        let firebaseUser = FirebaseApp.app() != nil ? Auth.auth().currentUser : nil
        let savedProvider = savedAuthProvider()
        let restoredProvider = savedProvider ?? firebaseUser.flatMap(Self.provider(from:))

        if let firebaseUser {
            restoreFirebaseSession(firebaseUser, provider: restoredProvider)
        } else if (savedProvider == nil || savedProvider == .apple),
                  let savedAppleID = UserDefaults.standard.string(forKey: appleUserDefaultsKey) {
            // Legacy Apple-only restore. Google sessions must come from Firebase so a saved
            // Firebase UID is never checked against Apple credential state.
            userIdentifier = savedAppleID
            isSignedIn = true
            loadSavedProfile()
            persistLocalSession(userId: savedAppleID, provider: .apple)

            #if !targetEnvironment(simulator)
            Task {
                await refreshAppleCredentialState(for: savedAppleID)
            }
            #endif
        }

        // Firebase Auth 상태 리스너 — 앱 재시작 시 Firebase 세션이 살아있으면 자동 복원
        // (Google 로그인 또는 UserDefaults가 없어도 Firebase 세션이 유효한 경우)
        if FirebaseApp.app() != nil {
            firebaseAuthHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                guard let self else { return }
                Task { @MainActor in
                    if let user {
                        self.restoreFirebaseSession(user, provider: Self.provider(from: user) ?? self.savedAuthProvider())
                    } else {
                        // Firebase도 로그아웃 → AuthService도 로그아웃
                        if self.isSignedIn {
                            self.clearLocalSession()
                        }
                    }
                }
            }
        }
    }

    deinit {
        if let handle = firebaseAuthHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Apple 로그인 요청 준비

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard isAppleSignInAvailable else {
            signInError = appleSignInAvailabilityMessage
            return
        }
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        beginSignIn(provider: .apple)
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    // MARK: - Apple 로그인 결과 처리

    func handleSignInResult(
        _ result: Result<ASAuthorization, Error>,
        backendService: BackendService? = nil
    ) async {
        defer { resetTransientAuthState(clearError: false) }
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                signInError = AppLanguage.current.text("Apple 로그인 응답을 해석하지 못했습니다.", "Couldn't read the Apple sign-in response.")
                return
            }

            userIdentifier = credential.user
            UserDefaults.standard.set(credential.user, forKey: appleUserDefaultsKey)
            persistLocalSession(userId: credential.user, provider: .apple)

            let name = Self.displayName(from: credential.fullName)
            if !name.isEmpty {
                userName = name
                UserDefaults.standard.set(name, forKey: "apple_user_name")
            }

            if let email = credential.email {
                userEmail = email
                UserDefaults.standard.set(email, forKey: "apple_user_email")
            }

            loadSavedProfile()
            signInError = nil
            isSignedIn = true

            if let backendService, FirebaseApp.app() != nil {
                guard
                    let nonce = currentNonce,
                    let identityTokenData = credential.identityToken,
                    let identityToken = String(data: identityTokenData, encoding: .utf8)
                else {
                    signInError = AppLanguage.current.text("Apple 로그인은 성공했지만 Firebase 인증에 필요한 토큰을 받지 못했습니다.", "Apple sign-in succeeded, but the Firebase token was missing.")
                    return
                }

                do {
                    try await backendService.signInWithFirebase(
                        idToken: identityToken,
                        nonce: nonce,
                        fullName: credential.fullName,
                        fallbackDisplayName: userName ?? AppLanguage.current.text("러너", "Runner")
                    )
                } catch {
                    signInError = AppLanguage.current.text("Apple 로그인은 성공했지만 Firebase 로그인에 실패했습니다: \(error.localizedDescription)", "Apple sign-in succeeded, but Firebase sign-in failed: \(error.localizedDescription)")
                }
            }

        case .failure(let error):
            let nsError = error as NSError
            // 1001 = 사용자가 취소, 1000 = 시뮬레이터 미지원
            if Self.isAppleCancellation(error) {
                signInError = nil
            } else if nsError.code == 1000 {
                #if targetEnvironment(simulator)
                signInError = AppLanguage.current.text("시뮬레이터에서는 Apple 로그인을 사용할 수 없습니다. 실제 기기에서 테스트해주세요.", "Apple sign-in is not available in the simulator. Test on a real device.")
                #else
                signInError = AppLanguage.current.text("Apple 로그인에 실패했습니다. 앱의 Sign in with Apple capability, Apple ID 로그인 상태, Firebase Apple 공급자 설정을 확인해주세요.", "Apple sign-in failed. Check the Sign in with Apple capability, Apple ID status, and Firebase Apple provider configuration.")
                #endif
            } else {
                signInError = AppLanguage.current.text("Apple 로그인 실패: \(error.localizedDescription)", "Apple sign-in failed: \(error.localizedDescription)")
            }
            print("Apple 로그인 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Google 로그인

    func signInWithGoogle(backendService: BackendService? = nil) async {
        beginSignIn(provider: .google)
        defer { resetTransientAuthState(clearError: false) }

        #if canImport(GoogleSignIn)
        guard let presentingViewController = Self.topViewController() else {
            signInError = AppLanguage.current.text("Google 로그인 화면을 띄울 수 없습니다.", "Couldn't present the Google sign-in screen.")
            return
        }
        guard FirebaseApp.app() != nil else {
            signInError = AppLanguage.current.text("Firebase가 설정되지 않았습니다. GoogleService-Info.plist 설정을 먼저 확인해주세요.", "Firebase is not configured. Check GoogleService-Info.plist first.")
            return
        }
        guard let clientID = googleClientID else {
            signInError = AppLanguage.current.text("Google 클라이언트 ID를 찾지 못했습니다.", "Couldn't find the Google client ID.")
            return
        }

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
                GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "AuthService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: AppLanguage.current.text("Google 로그인 결과가 비어 있습니다.", "The Google sign-in result was empty.")]
                        ))
                    }
                }
            }

            guard let backendService else {
                signInError = AppLanguage.current.text("Google 로그인 백엔드 서비스가 연결되지 않았습니다.", "The backend service for Google sign-in is not connected.")
                return
            }
            guard let idToken = result.user.idToken?.tokenString else {
                signInError = AppLanguage.current.text("Google ID 토큰을 가져오지 못했습니다.", "Couldn't get the Google ID token.")
                return
            }

            try await backendService.signInWithGoogle(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                fallbackDisplayName: result.user.profile?.name ?? AppLanguage.current.text("러너", "Runner")
            )

            userIdentifier = backendService.userId
            userName = backendService.currentUser?.displayName ?? result.user.profile?.name
            userEmail = backendService.currentUser?.email ?? result.user.profile?.email
            // Google 로그인도 앱 재시작 후 UserDefaults로 복원 가능하도록 저장
            if let uid = backendService.userId {
                persistLocalSession(userId: uid, provider: .google)
            }
            if let name = userName {
                UserDefaults.standard.set(name, forKey: "apple_user_name")
            }
            if let email = userEmail {
                UserDefaults.standard.set(email, forKey: "apple_user_email")
            }
            isSignedIn = true
        } catch {
            // -5 = 사용자가 취소(GIDSignInError.canceled), 취소는 에러 표시 안 함
            if Self.isGoogleCancellation(error) {
                signInError = nil
            } else {
                signInError = AppLanguage.current.text("Google 로그인 실패: \(error.localizedDescription)", "Google sign-in failed: \(error.localizedDescription)")
            }
        }
        #else
        signInError = AppLanguage.current.text("Google 로그인 SDK가 아직 프로젝트에 추가되지 않았습니다.", "The Google sign-in SDK is not yet added to the project.")
        #endif
    }

    // MARK: - 로그아웃

    func signOut(backendService: BackendService? = nil) {
        do {
            try backendService?.signOut()
        } catch {
            signInError = AppLanguage.current.text("로그아웃 실패: \(error.localizedDescription)", "Sign-out failed: \(error.localizedDescription)")
        }
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        clearLocalSession()
    }

    func clearLocalSession() {
        bleService?.disconnect()
        resetTransientAuthState()
        isSignedIn = false
        userIdentifier = nil
        UserDefaults.standard.removeObject(forKey: authUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: appleUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: authProviderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "apple_user_name")
        UserDefaults.standard.removeObject(forKey: "apple_user_email")
        userName = nil
        userEmail = nil
    }

    func resetTransientAuthState(clearError: Bool = true) {
        isAuthenticating = false
        selectedProvider = nil
        currentNonce = nil
        if clearError {
            signInError = nil
        }
    }

    // MARK: - 저장된 프로필 로드

    private func loadSavedProfile() {
        if userName == nil {
            userName = UserDefaults.standard.string(forKey: "apple_user_name")
        }
        if userEmail == nil {
            userEmail = UserDefaults.standard.string(forKey: "apple_user_email")
        }
    }

    private func beginSignIn(provider: AuthSignInProvider) {
        signInError = nil
        selectedProvider = provider
        isAuthenticating = true
    }

    private func persistLocalSession(userId: String, provider: AuthSignInProvider) {
        UserDefaults.standard.set(userId, forKey: authUserDefaultsKey)
        UserDefaults.standard.set(provider.rawValue, forKey: authProviderDefaultsKey)
        if provider == .google {
            UserDefaults.standard.removeObject(forKey: appleUserDefaultsKey)
        }
    }

    private func savedAuthProvider() -> AuthSignInProvider? {
        guard let rawValue = UserDefaults.standard.string(forKey: authProviderDefaultsKey) else {
            return nil
        }
        return AuthSignInProvider(rawValue: rawValue)
    }

    private func restoreFirebaseSession(_ user: User, provider: AuthSignInProvider?) {
        isSignedIn = true
        userIdentifier = user.uid
        if userName == nil {
            userName = user.displayName
                ?? UserDefaults.standard.string(forKey: "apple_user_name")
        }
        if userEmail == nil {
            userEmail = user.email
                ?? UserDefaults.standard.string(forKey: "apple_user_email")
        }
        if let provider {
            persistLocalSession(userId: user.uid, provider: provider)
        }
    }

    private func refreshAppleCredentialState(for userID: String) async {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                Task { @MainActor in
                    if let error {
                        print("Apple credential state 확인 실패: \(error.localizedDescription)")
                    }
                    switch state {
                    case .authorized:
                        self.isSignedIn = true
                    case .revoked, .notFound:
                        self.signOut()
                    default:
                        break
                    }
                    continuation.resume()
                }
            }
        }
    }

    private static func displayName(from fullName: PersonNameComponents?) -> String {
        [fullName?.familyName, fullName?.givenName]
            .compactMap { $0 }
            .joined()
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                return fallbackNonceString(length: length)
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func fallbackNonceString(length: Int) -> String {
        var buffer = ""
        while buffer.count < length {
            buffer += UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return String(buffer.prefix(length))
    }

    private var googleClientID: String? {
        if let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty {
            return clientID
        }

        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let config = NSDictionary(contentsOfFile: path),
            let clientID = config["CLIENT_ID"] as? String,
            !clientID.isEmpty
        else {
            return nil
        }

        return clientID
    }

    private static func provider(from user: User) -> AuthSignInProvider? {
        if user.providerData.contains(where: { $0.providerID == "google.com" }) {
            return .google
        }
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            return .apple
        }
        return nil
    }

    private static func isAppleCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.Code.canceled.rawValue {
            return true
        }
        return nsError.code == 1001
            || nsError.localizedDescription.localizedCaseInsensitiveContains("cancel")
    }

    private static func isGoogleCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = nsError.localizedDescription.lowercased()
        return nsError.code == -5
            || message.contains("canceled")
            || message.contains("cancelled")
            || message.contains("user canceled")
            || message.contains("sign-in flow")
    }

    @MainActor
    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let rootViewController = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController

        if let navigationController = rootViewController as? UINavigationController {
            return topViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = rootViewController as? UITabBarController {
            return topViewController(base: tabBarController.selectedViewController)
        }
        if let presented = rootViewController?.presentedViewController {
            return topViewController(base: presented)
        }
        return rootViewController
    }
}
