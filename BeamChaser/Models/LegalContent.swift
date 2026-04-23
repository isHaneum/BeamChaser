import Foundation

struct LegalDocumentDescriptor {
    let title: String
    let summary: String
    let body: String
}

enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case privacy
    case terms
    case location
    case health

    var id: String { rawValue }
}

enum LegalContent {
    static func document(for kind: LegalDocumentKind, language: AppLanguage = .current) -> LegalDocumentDescriptor {
        switch kind {
        case .privacy:
            return LegalDocumentDescriptor(
                title: language.text("개인정보 처리방침", "Privacy Policy"),
                summary: language.text("수집 항목, 이용 목적, 보관 기간, 계정 삭제 안내", "What we collect, why we use it, how long we keep it, and how account deletion works"),
                body: language.isEnglish ? privacyPolicyEnglish : privacyPolicy
            )
        case .terms:
            return LegalDocumentDescriptor(
                title: language.text("서비스 이용약관", "Terms of Service"),
                summary: language.text("계정, 커뮤니티, 러닝 기록 사용 시 기본 약관", "Basic terms covering accounts, Community, and running record usage"),
                body: language.isEnglish ? termsPolicyEnglish : termsPolicy
            )
        case .location:
            return LegalDocumentDescriptor(
                title: language.text("위치정보 수집·이용 동의", "Location Data Consent"),
                summary: language.text("러닝 경로·지도·메이트 기능을 위한 위치 처리 기준", "How location is processed for route tracking, maps, and mate features"),
                body: language.isEnglish ? locationPolicyEnglish : locationPolicy
            )
        case .health:
            return LegalDocumentDescriptor(
                title: language.text("건강 데이터 수집·이용 동의", "Health Data Consent"),
                summary: language.text("HealthKit 연동 범위와 저장 원칙", "What HealthKit data is used and how it is stored"),
                body: language.isEnglish ? healthPolicyEnglish : healthPolicy
            )
        }
    }

    static let privacyPolicy = """
    ■ 개인정보 처리방침

    1. 수집하는 개인정보 항목
    - 필수: 이름(닉네임), 이메일 주소, 소셜 로그인 식별자(Apple UID)
    - 선택: 프로필 사진, 신장
    - 선택: 연락처 이메일 정보(연락처 기반 친구 찾기 사용 시, 기기 내 매칭 전용)
    - 자동 수집: 기기 정보, 앱 이용 기록

    2. 개인정보 수집 목적
    - 회원 식별 및 서비스 제공
    - 러닝 기록 저장 및 통계 분석
    - 커뮤니티 기능(친구 추가, 피드, 러닝 메이트)

    3. 개인정보 보유 기간
    - 회원 탈퇴 시까지 보유하며, 탈퇴 후 즉시 파기합니다.
    - 단, 관계 법령에 따라 보존이 필요한 경우 해당 기간 동안 보관합니다.

    4. 제3자 제공
    - Firebase(Google) 인증 및 데이터 저장 서비스를 사용합니다.
    - 연락처 정보는 기기 내에서만 매칭하며 서버에 업로드하거나 저장하지 않습니다.
    - 본인 동의 없이 제3자에게 개인정보를 제공하지 않습니다.

    5. 이용자 권리
    - 개인정보 열람, 수정, 삭제를 언제든지 요청할 수 있습니다.
    - 설정 > 개인정보 & 계정에서 계정을 삭제할 수 있습니다.
    """

    static let privacyPolicyEnglish = """
    Privacy Policy

    1. Personal information we collect
    - Required: name (nickname), email address, social sign-in identifier (Apple UID)
    - Optional: profile photo, height
    - Optional: contact email addresses used only for on-device friend discovery
    - Automatically collected: device information and app usage records

    2. Why we collect personal information
    - To identify members and provide the service
    - To store running records and analyze statistics
    - To support community features such as friend requests, feed posts, and running mates

    3. Retention period
    - Data is kept until account deletion and deleted immediately after withdrawal.
    - If the law requires retention, data is stored for the required period.

    4. Third-party sharing
    - We use Firebase (Google) for authentication and data storage.
    - Contact data is processed only on the device for matching and is not uploaded or stored on the server.
    - We do not provide personal information to third parties without consent.

    5. Your rights
    - You may request access, correction, or deletion of your personal information at any time.
    - You can delete your account in Settings > Privacy & Account.
    """

    static let termsPolicy = """
    ■ 서비스 이용약관

    1. 서비스 목적
    - BeamChaser는 러닝 기록 측정, 커뮤니티 소통, 러닝 메이트 모집 기능을 제공하는 서비스입니다.

    2. 계정 및 이용 책임
    - 사용자는 Apple 또는 Google 로그인을 통해 계정을 생성할 수 있습니다.
    - 사용자는 본인의 계정 정보와 커뮤니티 활동에 대한 책임을 집니다.

    3. 러닝 기록 및 게시물
    - 사용자가 생성한 러닝 기록, 사진, 커뮤니티 게시물은 서비스 화면에 표시될 수 있습니다.
    - 타인의 권리를 침해하거나 부적절한 콘텐츠는 삭제될 수 있습니다.

    4. 커뮤니티 이용 제한
    - 욕설, 차별, 사칭, 스팸, 허위 정보 게시 등은 제한될 수 있습니다.
    - 반복 위반 시 게시물 삭제 또는 서비스 이용이 제한될 수 있습니다.

    5. 서비스 변경 및 종료
    - 서비스 기능은 개선을 위해 변경될 수 있으며, 중대한 변경 시 앱 내 또는 스토어 공지를 통해 안내합니다.

    6. 문의 및 탈퇴
    - 계정 삭제는 설정 > 개인정보 & 계정에서 진행할 수 있습니다.
    - 서비스 이용 중 문의가 있으면 개발자 연락처 또는 스토어 문의 채널을 이용해주세요.
    """

    static let termsPolicyEnglish = """
    Terms of Service

    1. Service purpose
    - BeamChaser provides running measurement, community interaction, and running mate recruitment features.

    2. Accounts and responsibilities
    - Users can create an account through Apple or Google sign-in.
    - Users are responsible for their account information and community activity.

    3. Running records and posts
    - Running records, photos, and community posts created by the user may be displayed inside the service.
    - Content that infringes the rights of others or is otherwise inappropriate may be removed.

    4. Community restrictions
    - Abuse, discrimination, impersonation, spam, or misleading information may be restricted.
    - Repeated violations may lead to content removal or limited service access.

    5. Service changes
    - Features may change as the service evolves. Material changes will be announced in-app or through the store listing.

    6. Contact and withdrawal
    - Account deletion is available in Settings > Privacy & Account.
    - For support, use the developer contact or the store support channel.
    """

    static let locationPolicy = """
    ■ 위치정보 수집·이용 동의

    1. 위치정보 수집 목적
    - 러닝 경로 측정 및 지도 표시
    - GPS 기반 거리·페이스 계산
    - 주변 러닝 모집 글 표시

    2. 수집하는 위치정보
    - 위도, 경도, 고도, 이동 속도
    - 러닝 세션 중 생성되는 경로 기록
    - 백그라운드 위치 정보는 사용자가 iOS에서 별도로 허용한 경우에만 사용됩니다.

    3. 위치정보 보유 기간
    - 러닝 기록에 포함되어 계정 유지 기간 동안 보관
    - 계정 삭제 시 함께 파기

    4. 위치정보 제3자 제공
    - 본인 동의 없이 위치정보를 제3자에게 제공하지 않습니다.
    - 러닝 메이트 기능 사용 시 모집 위치는 주변 사용자에게 공개되며, 앱 내에서는 완화된 위치 정보로 표시됩니다.

    5. 권한 거부 시 제한 사항
    - 위치 권한을 거부하면 러닝 측정, 지도, 메이트 찾기 기능을 사용할 수 없습니다.
    """

    static let locationPolicyEnglish = """
    Location Data Consent

    1. Why location is collected
    - To measure running routes and display them on the map
    - To calculate GPS-based distance and pace
    - To show nearby running mate posts

    2. What location data is collected
    - Latitude, longitude, altitude, and movement speed
    - Route records created during a running session
    - Background location is used only when the user explicitly allows it in iOS

    3. Retention period
    - Stored as part of running records while the account remains active
    - Deleted together with the account

    4. Third-party sharing
    - We do not provide location data to third parties without consent.
    - When using running mate features, meetup locations are shown to nearby users in a reduced-precision format.

    5. Limits when permission is denied
    - If location permission is denied, running measurement, maps, and mate discovery features are unavailable.
    """

    static let healthPolicy = """
    ■ 건강 데이터 수집·이용 동의

    1. 수집하는 건강 데이터
    - 운동(Workout): 러닝 기록 저장
    - 이동 거리(distanceWalkingRunning)
    - 활성 에너지 소모(activeEnergyBurned)
    - 심박수(heartRate) — 읽기 전용
    - 키(height) — 읽기 전용, 페이스 보정에 활용

    2. Apple 건강 앱 연동
    - 러닝 종료 후 운동 기록이 Apple 건강 앱에 자동 저장됩니다.
    - 건강 앱 데이터는 Apple의 HealthKit 프레임워크를 통해서만 접근합니다.

    3. 건강 데이터 외부 전송 여부
    - 건강 데이터는 기기 내 Apple 건강 앱에만 저장됩니다.
    - 서버로 전송되지 않으며 제3자에게 제공되지 않습니다.

    4. 권한 거부 시 제한 사항
    - 건강 데이터 권한을 거부하면 Apple 건강 앱 연동 및 칼로리/심박수 표시 기능이 비활성화됩니다.
    - BeamChaser의 기본 GPS 러닝 측정 기능은 정상 작동합니다.
    """

    static let healthPolicyEnglish = """
    Health Data Consent

    1. Health data we use
    - Workout: saving running workout records
    - distanceWalkingRunning
    - activeEnergyBurned
    - heartRate: read only
    - height: read only, used for pace calibration

    2. Apple Health integration
    - After a run ends, the workout record is automatically saved to Apple Health.
    - Health data is accessed only through Apple's HealthKit framework.

    3. External transmission
    - Health data is stored only in Apple Health on the device.
    - It is not sent to the server or shared with third parties.

    4. Limits when permission is denied
    - If health permission is denied, Apple Health sync and calorie or heart-rate display are disabled.
    - BeamChaser's basic GPS running features continue to work.
    """
}
