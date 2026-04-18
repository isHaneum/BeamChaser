import AuthenticationServices
import CryptoKit
import FirebaseCore
import Security
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import UIKit

/// Apple 로그인 인증 서비스
@MainActor
final class AuthService: ObservableObject {

    @Published var isSignedIn = false
    @Published var isAuthenticating = false
    @Published var userName: String?
    @Published var userEmail: String?
    @Published var userIdentifier: String?
    @Published var signInError: String?

    private let userDefaultsKey = "apple_user_id"
    private var currentNonce: String?

    var isGoogleSignInAvailable: Bool {
        #if canImport(GoogleSignIn)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }

    init() {
        if let savedID = UserDefaults.standard.string(forKey: userDefaultsKey) {
            userIdentifier = savedID
            isSignedIn = true
            loadSavedProfile()
            #if !targetEnvironment(simulator)
            Task {
                await refreshAppleCredentialState(for: savedID)
            }
            #endif
        }
    }

    // MARK: - Apple 로그인 요청 준비

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        signInError = nil
        isAuthenticating = true
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    // MARK: - Apple 로그인 결과 처리

    func handleSignInResult(
        _ result: Result<ASAuthorization, Error>,
        backendService: BackendService? = nil
    ) async {
        defer { isAuthenticating = false }
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Apple 로그인 응답을 해석하지 못했습니다."
                return
            }

            userIdentifier = credential.user
            UserDefaults.standard.set(credential.user, forKey: userDefaultsKey)

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
                    signInError = "Apple 로그인은 성공했지만 Firebase 인증에 필요한 토큰을 받지 못했습니다."
                    return
                }

                do {
                    try await backendService.signInWithFirebase(
                        idToken: identityToken,
                        nonce: nonce,
                        fullName: credential.fullName,
                        fallbackDisplayName: userName ?? "러너"
                    )
                } catch {
                    signInError = "Apple 로그인은 성공했지만 Firebase 로그인에 실패했습니다: \(error.localizedDescription)"
                }
            }

        case .failure(let error):
            let nsError = error as NSError
            // 1001 = 사용자가 취소, 1000 = 시뮬레이터 미지원
            if nsError.code == 1001 {
                signInError = nil // 사용자 취소는 에러 표시 안 함
            } else if nsError.code == 1000 {
                #if targetEnvironment(simulator)
                signInError = "시뮬레이터에서는 Apple 로그인을 사용할 수 없습니다. 실제 기기에서 테스트해주세요."
                #else
                signInError = "Apple 로그인에 실패했습니다. 앱의 Sign in with Apple capability, Apple ID 로그인 상태, Firebase Apple 공급자 설정을 확인해주세요."
                #endif
            } else {
                signInError = "Apple 로그인 실패: \(error.localizedDescription)"
            }
            print("Apple 로그인 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Google 로그인

    func signInWithGoogle(backendService: BackendService? = nil) async {
        signInError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        #if canImport(GoogleSignIn)
        guard let presentingViewController = await Self.topViewController() else {
            signInError = "Google 로그인 화면을 띄울 수 없습니다."
            return
        }
        guard FirebaseApp.app() != nil else {
            signInError = "Firebase가 설정되지 않았습니다. GoogleService-Info.plist 설정을 먼저 확인해주세요."
            return
        }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            signInError = "Google 클라이언트 ID를 찾지 못했습니다."
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
                            userInfo: [NSLocalizedDescriptionKey: "Google 로그인 결과가 비어 있습니다."]
                        ))
                    }
                }
            }

            guard let backendService else {
                signInError = "Google 로그인 백엔드 서비스가 연결되지 않았습니다."
                return
            }
            guard let idToken = result.user.idToken?.tokenString else {
                signInError = "Google ID 토큰을 가져오지 못했습니다."
                return
            }

            try await backendService.signInWithGoogle(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                fallbackDisplayName: result.user.profile?.name ?? "러너"
            )

            userIdentifier = backendService.userId
            userName = backendService.currentUser?.displayName ?? result.user.profile?.name
            userEmail = backendService.currentUser?.email ?? result.user.profile?.email
            isSignedIn = true
        } catch {
            signInError = "Google 로그인 실패: \(error.localizedDescription)"
        }
        #else
        signInError = "Google 로그인 SDK가 아직 프로젝트에 추가되지 않았습니다."
        #endif
    }

    // MARK: - 로그아웃

    func signOut(backendService: BackendService? = nil) {
        do {
            try backendService?.signOut()
        } catch {
            signInError = "로그아웃 실패: \(error.localizedDescription)"
        }
        clearLocalSession()
    }

    func clearLocalSession() {
        isSignedIn = false
        userIdentifier = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "apple_user_name")
        UserDefaults.standard.removeObject(forKey: "apple_user_email")
        userName = nil
        userEmail = nil
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
