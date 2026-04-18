# BeamChaser App Review Notes Template

최종 업데이트: 2026-04-17

아래 내용을 App Store Connect > App Review Information > Notes에 맞게 정리해 제출하세요.

---

## 1. 앱 개요

BeamChaser는 러닝 기록, BLE 장치 연동, Apple Health 연동, 커뮤니티 기능을 제공하는 러닝 앱입니다.

## 2. 로그인 안내

- 앱은 Apple 로그인을 지원합니다.
- 로그인 없이도 기본 탐색이 가능하지만, 커뮤니티 작성/참여 및 계정 동기화는 로그인 후 사용할 수 있습니다.
- 심사 계정이 필요하다면 아래 데모 계정을 기입하거나, Apple 로그인만으로 재현 가능하다고 명시하세요.

예시:

```
Demo Account
ID: review@example.com
PW: ********
```

## 3. 주요 재현 경로

1. 앱 실행
2. 온보딩에서 위치 권한과 건강 데이터 권한 확인
3. 홈에서 러닝 시작
4. 러닝 종료 후 기록 화면 및 프로필 통계 확인
5. 설정 > Apple 건강 앱 연동에서 권한 상태 확인

## 4. Apple Health / Location 안내

- HealthKit은 러닝 운동, 거리, 칼로리, 심박수 연동에 사용합니다.
- 위치 권한은 러닝 경로 기록과 러닝 메이트 기능에 사용합니다.
- 백그라운드 위치는 사용자가 iOS에서 별도로 허용한 경우에만 사용됩니다.

## 5. BLE 장치 안내

- BLE 장치가 없어도 기본 GPS 러닝 기능은 사용 가능합니다.
- 외부 하드웨어는 선택 기능이며, 심사 시 장치 없이도 핵심 러닝 플로우를 확인할 수 있습니다.

## 6. 커뮤니티 안내

- 커뮤니티는 로그인 후 활성화됩니다.
- 신고/차단/운영 연락처가 아직 준비되지 않았다면, 심사 제출 전 커뮤니티 작성 기능을 비활성화한 뒤 이 사실을 Notes에 명시하세요.

예시:

```
For this review build, content creation in Community is disabled while moderation tools are being finalized.
```

## 7. 계정 삭제 안내

- 설정 > 개인정보 & 계정 > 계정 삭제 에서 계정 삭제를 시작할 수 있습니다.
- 계정 삭제 시 앱 내 로컬 데이터와 서버 계정 데이터를 함께 삭제합니다.

## 8. 제출 전 체크

- 개인정보 처리방침 URL 입력
- Support URL 입력
- 새 Build 번호로 Archive
- TestFlight 내부 배포 확인
- 실기기에서 HealthKit / 위치 / BLE 재검증
