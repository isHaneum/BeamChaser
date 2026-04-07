# BeamChaser 디자인 시스템

> 파일 위치: `BeamChaser/Views/Components/DesignSystem.swift`

---

## 1. 디자인 원칙

- **다크 퍼스트**: 러닝 중 화면을 보는 상황을 우선. 기본 배경은 검정~짙은 회색
- **모노스페이스 숫자**: 페이스, 거리 등 숫자는 monospaced 폰트로 흔들림 없이 표시
- **Rounded 시스템 폰트**: UI 텍스트는 `.rounded` 디자인으로 부드러운 느낌
- **반응형 라이트/다크**: `RBColor` 전체가 라이트/다크 자동 전환 지원
- **오렌지 단일 Accent**: 강조색은 오렌지 계열 하나로 통일 (`Color.orange` + 그라디언트)

---

## 2. 색상 팔레트 (`RBColor`)

### Accent
| 토큰 | 값 | 용도 |
|------|-----|------|
| `RBColor.accent` | `Color.orange` | 버튼, 탭, 강조 텍스트 |
| `RBColor.accentGradient` | `#FF8C00 → #FF5900` (left→right) | Primary 버튼 배경 |

### 배경 (라이트/다크 적응형)
| 토큰 | 라이트 | 다크 | 용도 |
|------|--------|------|------|
| `RBColor.bg` | `white 96%` | `black` | 화면 배경 |
| `RBColor.cardBg` | `white 100%` | `white 11%` | 카드 배경 |
| `RBColor.cardBgLight` | `white 95%` | `white 15%` | 카드 내부 서브 영역 |

### 텍스트 (라이트/다크 적응형)
| 토큰 | 라이트 | 다크 | 용도 |
|------|--------|------|------|
| `RBColor.textPrimary` | `white 10%` (거의 검정) | `white` | 본문, 수치 |
| `RBColor.textSecondary` | `white 45%` (중회색) | `white 65%` | 부제목, 단위 |
| `RBColor.textTertiary` | `white 60%` (연회색) | `white 45%` | 힌트, 레이블 |

### 경계선
| 토큰 | 라이트 | 다크 | 용도 |
|------|--------|------|------|
| `RBColor.divider` | `white 88%` (연회색) | `white 20%` | 구분선 |

### 상태 색상
| 토큰 | 값 | 용도 |
|------|-----|------|
| `RBColor.success` | `#33D966` (초록) | 성공, 적정 페이스, GPS 강함 |
| `RBColor.danger` | `#FF4D4D` (빨강) | 오류, 느린 페이스, GPS 약함 |
| `RBColor.laserRed` | `#FF2626` (강한 빨강) | 레이저 마커 글로우 |

### 페이스 상태 색상 (RunActiveView)
| 상태 | 색상 | 조건 |
|------|------|------|
| Ahead (앞섬) | `RBColor.success` (초록) | 레이저보다 앞 |
| On Pace (적정) | `RBColor.accent` (오렌지) | ±기준 내 |
| Behind (뒤처짐) | `RBColor.danger` (빨강) | 레이저보다 뒤 |

---

## 3. 타이포그래피 (`RBFont`)

| 함수 | weight | design | 용도 | 주사용 사이즈 |
|------|--------|--------|------|--------------|
| `RBFont.hero(_)` | `.black` | `.rounded` | 화면 타이틀, 큰 숫자 제목 | 24, 32, 48 |
| `RBFont.metric(_)` | `.heavy` | `.monospaced` | 페이스·거리·시간 수치 | 11, 14, 22, 28, 32, 36 |
| `RBFont.label(_)` | `.semibold` | `.rounded` | 버튼 텍스트, 항목 이름 | 12, 14, 15, 16, 17 |
| `RBFont.caption(_)` | `.medium` | `.rounded` | 보조 설명, 단위, 레이블 | 9, 10, 11, 12, 13 (기본 11) |

### 레터스페이싱 (tracking)
- 섹션 헤더 / UPPERCASE 레이블: `.tracking(1)` ~ `.tracking(1.2)`
- 그 외 일반 텍스트: 기본값

---

## 4. 공통 컴포넌트

### `RBPrimaryButton`
```
┌──────────────────────────────────┐
│  [icon]  타이틀 텍스트            │  height: 56pt
└──────────────────────────────────┘
```
- 배경: `RBColor.accentGradient` (Capsule)
- 텍스트/아이콘: `.white`, `RBFont.label(17)`
- 너비: `maxWidth: .infinity`

### `RBCard`
- 내부 패딩: `16pt`
- 배경: `RBColor.cardBg`
- 모서리: `cornerRadius 20, .continuous`

### `MetricView`
```
   LABEL         ← RBFont.caption(10), textSecondary, tracking 1.2, uppercase
  000.00 단위    ← RBFont.metric(valueSize), textPrimary + caption(12), textSecondary
```
- 기본 수치 사이즈: 36pt
- minimumScaleFactor: 0.4 (긴 숫자 자동 축소)

### `LaserDot`
- 레이저 위치 마커 (빨간 글로우 원)
- 기본: `size: 16`, `glowRadius: 10`
- `RBColor.laserRed` + `.shadow(color: laserRed.opacity(0.7), radius: glowRadius)`
- `.overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))`

### `StatusBadge`
```
[icon]  텍스트    ← Capsule 배경, 색상.opacity(0.15)
```
- padding: `12pt` 좌우, `6pt` 상하
- 텍스트: `RBFont.label(12)`

---

## 5. 레이아웃 규칙

### 패딩
| 상황 | 값 |
|------|-----|
| 화면 좌우 패딩 | `16pt` (일반), `20pt` (러닝 오버레이) |
| 카드 내부 패딩 | `14pt` ~ `16pt` |
| 섹션 간격 | `16pt` ~ `20pt` |
| 버튼 높이 | `56pt` (Primary), `48pt` (Secondary) |
| 아이콘 프레임 | `32pt` 고정 너비 (설정 목록 정렬용) |

### CornerRadius
| 요소 | radius | style |
|------|--------|-------|
| 화면 카드 (기본) | `16pt` | `.continuous` |
| `RBCard` 컴포넌트 | `20pt` | `.continuous` |
| 하단 오버레이 패널 | `28pt` | `.continuous` |
| 소형 배지 / 칩 | `Capsule` | — |
| 버튼 (Primary) | `Capsule` | — |

---

## 6. 화면별 디자인 패턴

### 홈 화면 (HomeView)
- 지도 풀스크린 (`ignoresSafeArea`)
- 하단 드래그 패널: collapsed `80pt` ↔ expanded (동적 높이)
- `.ultraThinMaterial` 사용 금지 → 단색 `RBColor.cardBg` 사용
- map style: `.standard(pointsOfInterest: .excludingAll)`

### 러닝 실행 화면 (RunActiveView)
- 강제 다크모드: `.preferredColorScheme(.dark)`
- 지도 풀스크린 + 상단 오버레이 + 하단 오버레이 ZStack 구조
- 하단 패널: `.ultraThinMaterial` (`.dark` environment) + `cornerRadius 28`
- 페이스 상태 배너: 상태에 따라 배경색 변화, `opacity(0.85)`, `shadow radius 8`
- 레이저 갭 바: `GeometryReader`, 바 `height: 6pt`, 마커 `height: 12pt`
- 메트릭 패널: compact(3개) ↔ expanded(6개) 전환, `.spring(response: 0.35, dampingFraction: 0.8)`

### 기록/프로필/설정 화면
- 배경: `RBColor.bg.ignoresSafeArea()`
- `NavigationStack` + `.navigationTitle` + `.navigationBarTitleDisplayMode(.large)`
- 섹션 카드: `VStack(spacing: 0)` 내부 항목 + `Divider().padding(.leading, 58)` 구분
- 아이콘 너비 `32pt` 고정으로 텍스트 정렬

---

## 7. 애니메이션

| 사용처 | 애니메이션 |
|--------|-----------|
| 드래그 패널 펼침/접힘 | `.spring(response: 0.35, dampingFraction: 0.8)` |
| 카드 확장 (PaceSetup) | `.opacity` transition |
| 지도 카메라 이동 | `.easeInOut(duration: 0.6)` |
| 일시정지 버튼 깜빡임 | `.easeInOut(duration: 0.7).repeatForever(autoreverses: true)` |

---

## 8. 아이콘 규칙 (SF Symbols)

| 화면 요소 | SF Symbol | 크기 |
|-----------|-----------|------|
| 탭바 홈 | `house.fill` | 시스템 기본 |
| 탭바 기록 | `clock.arrow.circlepath` | 시스템 기본 |
| 탭바 커뮤니티 | `person.2.fill` | 시스템 기본 |
| 탭바 프로필 | `person.fill` | 시스템 기본 |
| BLE 연결 | `antenna.radiowaves.left.and.right` | 16pt |
| 배터리 | `battery.100` ~ `battery.0` | 동적 |
| GPS 신호 | 커스텀 막대 3개 (`RoundedRectangle`) | — |
| 설정 | `gearshape.fill` | 16pt |
| 러닝 시작 | `figure.run` | — |
| 레이저 | `laser.burst` / `scope` | — |

---

## 9. 다크모드 대응

```swift
// Color 확장으로 라이트/다크 분기
extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
```

- `RBColor` 내 모든 배경/텍스트/경계선 색상이 이 확장 사용
- 러닝 화면만 `.preferredColorScheme(.dark)` 강제
- 그 외 화면은 `@AppStorage("appearanceMode")` 사용자 설정 따름
- 탭바 tint: `RBColor.accent` (라이트/다크 모두 동일한 오렌지)

---

## 10. 주의 / 컨벤션

- 새 색상 직접 하드코딩 금지 → `RBColor` 토큰 사용
- 새 폰트 직접 하드코딩 금지 → `RBFont` 함수 사용
- `Divider`는 항상 `.overlay(RBColor.divider)` 적용 (기본 Divider는 라이트/다크 대응 안 됨)
- 카드 내부 구분선은 `.padding(.leading, 58)` (아이콘 32pt + 패딩 14pt + 여백 12pt)
- `RBPrimaryButton`은 전체 너비 CTA에만 사용
- 숫자 표시는 반드시 `RBFont.metric()`으로 monospaced 유지
