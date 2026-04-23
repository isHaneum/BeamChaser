# BeamChaser App Review Notes Template

최종 업데이트: 2026-04-18

아래 내용을 App Store Connect > App Review Information > Notes에 맞게 정리해 제출하세요.

---

## 1. 기본 설명 템플릿

BeamChaser is a running app that supports GPS run tracking, optional BLE laser device integration, Apple Health integration, social community features, and optional contact-based runner discovery.

## 2. 로그인 안내 템플릿

- 현재 빌드는 Apple Sign In 및 Google Sign-In을 지원합니다.
- 로그인 없이도 일부 탐색은 가능하지만, 커뮤니티 작성/참여, 친구 요청, 계정 동기화는 로그인 후 사용할 수 있습니다.
- 심사 계정을 제공할 경우 아래 형식으로 기입합니다.

예시:

```text
Demo Account
ID: review@example.com
PW: ********
```

로그인 없는 재현만 허용할 경우 예시:

```text
App Review can verify the core running flow without signing in. Social and account-sync features require sign-in.
```

## 3. 주요 재현 경로 템플릿

1. Launch the app and complete onboarding.
2. Allow Location and Health permissions when prompted.
3. Start a run from the Home screen.
4. End the run and verify the result in History and Profile.
5. Open Settings > Apple Health Integration to confirm the permission state.
6. Sign in to verify Community, friend requests, and contact-based discovery.

## 4. 권한 안내 템플릿

- HealthKit is used to read/write workout data such as distance, calories, and heart rate.
- Location is used to record running routes and support background run tracking when the user allows it.
- Contacts permission is optional and used only to help discover runners already known to the user.
- Contact matching is performed on-device for discovery UI and the full address book is not uploaded as a server-side contact sync feature.

## 5. BLE 장치 안내 템플릿

- The external BLE laser device is an optional accessory feature.
- Core GPS running can be reviewed without the hardware.
- If hardware is not available during review, reviewers can still validate the main run flow, history, profile, and most settings screens.

## 6. 커뮤니티 안내 템플릿

- Community features become available after sign-in.
- The app includes report and block actions for user-generated content.
- Friend relationships use a request/accept/reject flow rather than one-tap forced addition.
- Optional contact-based runner suggestions are shown only when the user grants Contacts access.

필요 시 예시 문구:

```text
Community features require sign-in. Users can report posts and block other users from the in-app community interface.
```

## 7. 계정 삭제 안내 템플릿

- Users can start account deletion from Settings > Privacy & Account > Delete Account.
- The app removes account-linked app data and related social data as part of the deletion flow.

## 8. 운영 연락처 템플릿

심사 노트 또는 Support URL에서 운영 문의 채널을 명확히 연결합니다.

예시:

```text
For support or moderation questions, contact: <support email or support URL>
```

## 9. 제출 직전 체크

- Privacy Policy URL 입력
- Support URL 입력
- 새 Build 번호로 Archive
- TestFlight 내부 배포 확인
- 실기기에서 HealthKit / Location / Contacts / BLE 재검증
