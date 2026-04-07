# BeamChaser (BeamChaser) 문서 인덱스

> 레이저 페이스메이커 러닝 앱 — 전체 기능 문서

---

## 📂 문서 목록

| # | 문서 | 설명 |
|---|------|------|
| 00 | [앱 개요](00_앱_개요.md) | 기술 스택, 탭 구조, 네비게이션 플로우, 디자인 시스템 |
| 01 | [홈 화면](01_홈_화면.md) | 전체 화면 지도, 드래그 패널, 장치 칩, 시작 버튼 |
| 02 | [장치 연결](02_장치_연결.md) | BLE 스캔/연결, 서보 슬라이더, 레이저 테스트 |
| 03 | [러닝 기능](03_러닝_기능.md) | 페이스 설정, 러닝 실행 화면, 실시간 지도 |
| 04 | [러닝 기록](04_러닝_기록.md) | 기록 목록, 상세 뷰, 공유 카드 |
| 05 | [프로필](05_프로필.md) | Apple 로그인, 레벨/뱃지 시스템, 월간 목표 |
| 06 | [커뮤니티](06_커뮤니티.md) | 러닝 메이트 모집, 피드 게시글 |
| 07 | [게임 모드](07_게임_모드.md) | 4종 게임 모드 (준비 중) |
| 08 | [설정](08_설정.md) | 장치, 레이저 캘리브레이션, 러닝, 음성, 건강, 외관 |
| 09 | [BLE 장치 통신](09_BLE_장치_통신.md) | HW 구성, 프로토콜, BLEService, Arduino 펌웨어 |
| 10 | [서비스 엔진](10_서비스_엔진.md) | Location, RunSession, PaceMaker, HealthKit, Auth |
| 11 | [데이터 모델](11_데이터_모델.md) | 전체 데이터 구조체/열거형 정의 |

---

## 프로젝트 정보

| 항목 | 값 |
|------|-----|
| 앱 이름 | BeamChaser |
| Bundle ID | `com.goldmine.beamchaser` |
| 플랫폼 | iOS 17.0+ |
| 프레임워크 | SwiftUI |
| 빌드 도구 | XcodeGen (`project.yml`) |
| GitHub | [isHaneum/BeamChaser](https://github.com/isHaneum/BeamChaser) |

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────┐
│                  Views (SwiftUI)             │
│  Home │ Running │ History │ Profile │ ...    │
├─────────────────────────────────────────────┤
│              Services (엔진 레이어)           │
│  RunSessionManager ← PaceMakerEngine        │
│  LocationService   ← HealthKitService       │
│  BLEService        ← AuthService            │
├─────────────────────────────────────────────┤
│              Models (데이터 레이어)           │
│  RunRecord │ RunnerProfile │ BLEProtocol     │
├─────────────────────────────────────────────┤
│              External                        │
│  CoreBluetooth │ CoreLocation │ HealthKit    │
│  MapKit        │ CMPedometer  │ AVFoundation │
└─────────────────────────────────────────────┘
```

---

## 주요 흐름 요약

### 러닝 플로우
```
홈 → 페이스 설정 → 러닝 실행 → 완료 → 기록 저장
         │              │
         └─ BLE 연동 ───┘─→ 레이저 실시간 제어
```

### 데이터 플로우
```
GPS + 만보기 → LocationService → RunSessionManager → RunRecord (저장)
                                       ↕
BLE 장치   → BLEService       → PaceMakerEngine → 레이저 Zone 제어
                                       ↕
                              HealthKitService → Apple 건강 앱
```
