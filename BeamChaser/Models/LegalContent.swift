import Foundation

struct LegalDocumentDescriptor {
    let title: String
    let summary: String
    let body: String
}

enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case privacy
    case location
    case health

    var id: String { rawValue }
}

enum LegalContent {
    static func document(for kind: LegalDocumentKind) -> LegalDocumentDescriptor {
        switch kind {
        case .privacy:
            return LegalDocumentDescriptor(
                title: "개인정보 처리방침",
                summary: "수집 항목, 이용 목적, 보관 기간, 계정 삭제 안내",
                body: privacyPolicy
            )
        case .location:
            return LegalDocumentDescriptor(
                title: "위치정보 수집·이용 동의",
                summary: "러닝 경로·지도·메이트 기능을 위한 위치 처리 기준",
                body: locationPolicy
            )
        case .health:
            return LegalDocumentDescriptor(
                title: "건강 데이터 수집·이용 동의",
                summary: "HealthKit 연동 범위와 저장 원칙",
                body: healthPolicy
            )
        }
    }

    static let privacyPolicy = """
    ■ 개인정보 처리방침

    1. 수집하는 개인정보 항목
    - 필수: 이름(닉네임), 이메일 주소, 소셜 로그인 식별자(Apple UID)
    - 선택: 프로필 사진, 신장
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
    - 본인 동의 없이 제3자에게 개인정보를 제공하지 않습니다.

    5. 이용자 권리
    - 개인정보 열람, 수정, 삭제를 언제든지 요청할 수 있습니다.
    - 설정 > 개인정보 & 계정에서 계정을 삭제할 수 있습니다.
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
    - RunBeam의 기본 GPS 러닝 측정 기능은 정상 작동합니다.
    """
}
