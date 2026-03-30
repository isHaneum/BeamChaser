import AuthenticationServices
import SwiftUI

/// Apple 로그인 인증 서비스
@MainActor
final class AuthService: ObservableObject {

    @Published var isSignedIn = false
    @Published var userName: String?
    @Published var userEmail: String?
    @Published var userIdentifier: String?
    @Published var signInError: String?

    private let userDefaultsKey = "apple_user_id"

    init() {
        if let savedID = UserDefaults.standard.string(forKey: userDefaultsKey) {
            userIdentifier = savedID
            isSignedIn = true
            loadSavedProfile()
        }
    }

    // MARK: - Apple 로그인 결과 처리

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            userIdentifier = credential.user
            UserDefaults.standard.set(credential.user, forKey: userDefaultsKey)

            if let fullName = credential.fullName {
                let name = [fullName.familyName, fullName.givenName]
                    .compactMap { $0 }
                    .joined(separator: "")
                if !name.isEmpty {
                    userName = name
                    UserDefaults.standard.set(name, forKey: "apple_user_name")
                }
            }

            if let email = credential.email {
                userEmail = email
                UserDefaults.standard.set(email, forKey: "apple_user_email")
            }

            loadSavedProfile()
            signInError = nil
            isSignedIn = true

        case .failure(let error):
            let nsError = error as NSError
            // 1001 = 사용자가 취소, 1000 = 시뮬레이터 미지원
            if nsError.code == 1001 {
                signInError = nil // 사용자 취소는 에러 표시 안 함
            } else if nsError.code == 1000 {
                signInError = "시뮬레이터에서는 Apple 로그인을 사용할 수 없습니다. 실제 기기에서 테스트해주세요."
            } else {
                signInError = "로그인에 실패했습니다. 다시 시도해주세요."
            }
            print("Apple 로그인 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 시뮬레이터 테스트 로그인

    #if targetEnvironment(simulator)
    func simulatorSignIn() {
        let testID = "simulator_test_user"
        userIdentifier = testID
        userName = "테스트 유저"
        userEmail = "test@runbeam.app"
        UserDefaults.standard.set(testID, forKey: userDefaultsKey)
        UserDefaults.standard.set(userName, forKey: "apple_user_name")
        UserDefaults.standard.set(userEmail, forKey: "apple_user_email")
        signInError = nil
        isSignedIn = true
    }
    #endif

    // MARK: - 로그아웃

    func signOut() {
        isSignedIn = false
        userIdentifier = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
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
}
