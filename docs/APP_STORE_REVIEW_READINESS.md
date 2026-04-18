# BeamChaser App Store Review Readiness

최종 업데이트: 2026-04-17

## 1. 이번 점검에서 바로 반영한 항목

- Google Sign-In SDK가 실제로 포함되지 않은 상태에서 로그인 버튼이 노출되던 문제 수정
- 설정 화면에 in-app 법률 문서(개인정보/위치/건강 데이터) 접근 경로 추가
- 설정 화면에서 계정 삭제를 직접 시작할 수 있는 플로우 추가
- 계정 삭제 시 프로필, 러닝 기록, 커뮤니티 글/댓글/좋아요/참여 상태 정리 로직 추가
- 커뮤니티 메이트 모집 좌표를 소수점 3자리로 완화해 정밀 위치 노출 완화
- 앱 레벨 `PrivacyInfo.xcprivacy` 추가 (`UserDefaults`, reason `CA92.1`)
- iOS / watchOS entitlements에 HealthKit entitlement 명시
- 위치 권한 흐름에서 `When In Use -> Always` 승격 요청 가능하도록 보정

## 2. App Review 전에 반드시 수동 확인할 항목

### A. App Store Connect 메타데이터

- 개인정보 처리방침 URL 등록
- 지원 URL 등록
- 마케팅 URL이 있다면 최신 상태로 점검
- 앱 설명/스크린샷/키워드에 미완성 문구 제거

### B. Firebase 운영 설정

- Firestore Rules 실제 배포
- Storage Rules 실제 배포
- 필요한 composite index 생성
- Apple 로그인 / Firebase Authentication 활성화 상태 확인
- 심사용 데모 계정 또는 리뷰 재현 절차를 리뷰 노트에 제공

### C. HealthKit / 위치 권한 실기기 점검

- 현재 로컬 Debug 빌드에서는 `com.apple.developer.healthkit` entitlement가 실제 `.xcent`에 포함되는 것까지 확인함
- 다만 배포용 Archive에서도 같은 entitlement가 유지되는지, 그리고 App ID / Distribution Profile이 HealthKit capability를 포함하는지는 Organizer 아카이브 기준으로 다시 확인해야 함
- 실제 iPhone에서 HealthKit 권한 요청 성공 여부
- Apple Watch 착용 상태에서 심박수 실시간 반영 여부
- 러닝 종료 후 운동/경로/거리 저장 여부
- 위치 `항상 허용` 후 백그라운드 이동 시 경로 기록 유지 여부

## 3. 현재 남아 있는 심사 리스크

### 1) 커뮤니티 UGC 기능

Apple App Review Guideline 1.2 기준으로 다음 항목이 아직 완성되지 않았습니다.

- 게시 전 유해 콘텐츠 필터링
- 신고 기능
- 사용자 차단 기능
- 운영 연락처 공개 및 대응 프로세스

권장 대응:

1. 심사 전까지 커뮤니티 작성/댓글 기능을 비활성화하거나
2. 신고/차단/운영 연락처를 구현한 뒤 제출

### 1-1) Firebase Rules 보안 리스크

- 현재 저장소에는 Firestore / Storage Rules가 실제 rules 파일이 아니라 주석 예시로만 남아 있음
- 특히 예시 Firestore Rules의 `feedPosts` 업데이트 권한은 너무 넓어서, 그대로 배포하면 로그인 사용자라면 다른 사람 게시글도 수정할 수 있는 구조가 됨

권장 대응:

1. `firestore.rules`, `storage.rules`, `firebase.json`을 별도 파일로 분리
2. 게시글 본문 수정, 좋아요, 댓글 추가를 각각 분리한 최소 권한 규칙으로 재작성
3. 배포 후 Emulator 또는 실제 계정으로 회귀 테스트

### 2) 개인정보/앱 프라이버시 폼

`PrivacyInfo.xcprivacy`는 required reason API 대응만 반영했습니다.
App Store Connect의 App Privacy 섹션은 별도로 직접 작성해야 합니다.

현재 코드상 검토 대상:

- 이름/닉네임
- 이메일
- 사용자 식별자
- 위치
- 사진
- 건강/피트니스 데이터
- 사용 데이터(러닝 기록, 커뮤니티 활동)

### 3) 법률 문구와 실제 운영 정책의 일치

- 계정 삭제 요청을 실제 운영 서버/백업/로그 정책까지 반영하는지 확인
- 보존 의무 데이터가 있다면 앱과 개인정보 처리방침에 명시
- 외부 지원 채널(이메일 또는 웹 문의) 운영 주체 확정 필요

## 4. 제출 직전 체크리스트

1. `xcodegen`으로 프로젝트 재생성
2. `BeamChaser` iOS 빌드 실행
3. 현재 스킴에 test action이 없어 `xcodebuild test`는 실패하므로, 최소 smoke test 또는 UI test 스킴을 별도로 준비
4. 실기기에서 Apple 로그인 / HealthKit / 위치 / BLE / 커뮤니티 주요 동선 확인
5. 새 빌드 번호로 Archive
6. Organizer > Distribute App
7. App Store Connect에서 빌드 처리 완료 확인
8. TestFlight 내부 배포 후 재설치 검증
9. 리뷰 노트 작성

## 5. 리뷰 노트에 넣을 권장 내용

- Apple 로그인 테스트 절차
- HealthKit 권한 요청 목적과 확인 경로
- 위치 권한이 필요한 이유와 러닝 재현 순서
- BLE 장치가 없어도 기본 GPS 러닝 기능은 사용 가능하다는 점
- 커뮤니티 기능이 로그인 후에만 활성화된다는 점

## 6. 제출 보류 권장 조건

아래 중 하나라도 미완료면 외부 심사 제출은 보류하는 편이 안전합니다.

- 개인정보 처리방침 URL 미등록
- Firebase Rules 미배포
- Firebase Rules가 예시 주석 상태이거나 과도하게 느슨한 상태
- HealthKit 실기기 저장 미검증
- 커뮤니티 UGC 신고/차단 정책 미정
