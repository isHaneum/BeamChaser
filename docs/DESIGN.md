# BeamChaser Mobile Running DESIGN.md

최종 업데이트: 2026-04-28

기준 파일:
- `BeamChaser/Views/Components/DesignSystem.swift`
- `BeamChaser/Views/Running/RunActiveView.swift`
- `BeamChaser/Views/Profile/RunShareScreen.swift`
- `RunBeamAndroid/src/screens/RunActiveScreen.js`
- `RunBeamAndroid/src/screens/RunDetailScreen.js`
- `RunBeamAndroid/src/components/TabBar.js`

## 1. Purpose

이 문서는 BeamChaser 전용 모바일 러닝 앱 디자인 시스템이다.

이 문서는 웹 랜딩페이지 문법을 가져다 쓰기 위한 문서가 아니다. `awesome-design-md`의 구조적 장점은 참고하되, 모든 규칙은 iPhone/Android 러닝 화면 기준으로 다시 정의한다.

핵심 원칙:
- 숫자는 장식보다 먼저 읽혀야 한다.
- 러닝 중 화면은 광고형 hero 레이아웃이 아니라 즉시 판독 가능한 계기판이어야 한다.
- 값과 단위는 항상 한 줄에 유지한다.
- BeamChaser의 브랜드 강조는 오렌지 하나로 끝낸다.
- blur, 반투명, 배경 사진은 정보 전달을 방해하지 않는 범위에서만 사용한다.
- Dynamic Island, status bar, home indicator, 하단 제스처 영역을 침범하지 않는다.

## 2. Mobile Conversion Rule

웹/랜딩페이지 스타일을 모바일 러닝 화면으로 변환할 때 다음 규칙을 강제한다.

- `hero section`, `marketing split layout`, `full-bleed text over art`를 그대로 사용하지 않는다.
- hover, sticky, mouse-parallax, wide container, vh 기반 배치는 모바일 앱 토큰으로 변환한다.
- 배경 중심 디자인이 아니라 metric 중심 디자인으로 변환한다.
- card 위 card를 겹쳐 깊이를 만드는 대신, top bar, hero metrics, bottom dock의 3단 구조로 정리한다.
- 정보 판독이 필요한 영역은 유리질감보다 solid surface 또는 70% 이상 불투명 surface를 우선한다.

웹 개념에서 모바일 개념으로의 변환:

| Web Concept | BeamChaser Mobile Replacement |
|---|---|
| wide hero container | safe-area shell + centered metric block |
| hover emphasis | pressed, selected, disabled, running, paused state |
| backdrop blur only | blur + black overlay `0.45 ~ 0.65` |
| split 2-column layout | vertical stack or bottom dock |
| floating CTA over content | dock-contained CTA with reserved safe area |
| decorative glass cards | high-contrast metric plate |

## 3. Visual Theme & Atmosphere

BeamChaser는 `hardware pacing coach + focused run instrument`의 분위기를 유지한다.

- 배경은 어둡고 차분해야 하지만, 정보는 뿌옇거나 흐릿하면 안 된다.
- 주요 수치는 명확한 백색 또는 고대비 밝은 중성색으로 고정한다.
- 상태 강조는 오렌지, 성공은 녹색, 경고는 적색으로 제한한다.
- 과한 네온, 과한 bloom, 과한 glassmorphism, 과한 uppercase display는 금지한다.
- music, map, share 페이지는 분위기를 달리할 수 있지만 숫자 토큰은 동일해야 한다.

## 4. Color Tokens

### 4.1 Core Tokens

| Token | Hex | Usage |
|---|---|---|
| `bg/base` | `#0B0D12` | 기본 러닝 화면 배경 |
| `bg/elevated` | `#151922` | 카드, 도크, 상단 상태 바 배경 |
| `bg/solidStrong` | `rgba(11,13,18,0.88)` | top metric bar, overlay shell |
| `bg/solidSoft` | `rgba(18,22,30,0.76)` | secondary floating surfaces |
| `brand/primary` | `#FF6A00` | BeamChaser 주요 강조 |
| `brand/primaryPressed` | `#E85F00` | 버튼 pressed |
| `brand/surface` | `rgba(255,106,0,0.14)` | 선택 상태 배경 |
| `text/primary` | `#FFFFFF` | 핵심 수치, 핵심 CTA 텍스트 |
| `text/secondary` | `#D4D7DD` | 보조 정보 |
| `text/tertiary` | `#9AA3B2` | 캡션, 단위, 메타 라벨 |
| `text/inverse` | `#111111` | 밝은 배경 위 텍스트 |
| `line/subtle` | `rgba(255,255,255,0.10)` | 경계선 |
| `line/strong` | `rgba(255,255,255,0.18)` | 강조 경계선 |
| `state/success` | `#34C759` | 안정 페이스, 연결됨 |
| `state/warning` | `#FF9F0A` | 센서 추정, 주의 |
| `state/danger` | `#FF453A` | 연결 끊김, 페이스 이탈 |
| `map/fast` | `#5AC8FA` | 빠른 구간 |
| `map/steady` | `#34C759` | 정상 구간 |
| `map/slow` | `#FF453A` | 느린 구간 |
| `overlay/black45` | `rgba(0,0,0,0.45)` | 최소 overlay |
| `overlay/black55` | `rgba(0,0,0,0.55)` | 기본 overlay |
| `overlay/black65` | `rgba(0,0,0,0.65)` | 강한 overlay |

### 4.2 Color Rules

- 배경 이미지 또는 blur 위에는 반드시 black overlay `0.45 ~ 0.65`를 적용한다.
- primary metric은 opacity `1.0`이다. 투명도로 계층을 만들지 않는다.
- top metric bar는 solid 또는 `70%` 이상 불투명 배경을 사용한다.
- pause 버튼 본체는 브랜드 오렌지 또는 고대비 neutral surface를 사용하고 배경과 시각적으로 분리한다.
- 브랜드 보조색을 여러 개 만들지 않는다. 오렌지 외 색상은 상태 의미를 갖는 경우에만 사용한다.

## 5. Typography Tokens

### 5.1 Font Families

- iOS: `SF Pro Display`, `SF Pro Text`
- Android / Expo: 시스템 sans 우선, 숫자는 가능한 한 tabular numeric variant 사용
- 선택 프리셋은 허용하되, 러닝 수치 토큰의 크기와 weight는 프리셋과 무관하게 유지한다.

### 5.2 Type Scale

| Token | Size | Weight | Line Height | Usage |
|---|---|---|---|---|
| `display/metricHero` | `64 ~ 76` | `800 ~ 900` | `0.96em` | 거리, 대형 수치 |
| `display/metricTime` | `30 ~ 36` | `800` | `1.0em` | 경과 시간 |
| `display/metricSecondary` | `22 ~ 28` | `800` | `1.0em` | 보조 지표 |
| `text/unitHero` | `18 ~ 22` | `700` | `1.0em` | `km`, `/km` |
| `text/labelStrong` | `13 ~ 15` | `700` | `1.2em` | 상태 라벨, 버튼 |
| `text/body` | `14 ~ 16` | `500 ~ 600` | `1.35em` | 일반 설명 |
| `text/caption` | `11 ~ 12` | `600 ~ 700` | `1.25em` | 캡션, 상태 보조 |
| `text/eyebrow` | `10 ~ 11` | `700 ~ 800` | `1.2em` | section label |

### 5.3 Typography Rules

- 러닝 수치에는 장식 serif를 사용하지 않는다.
- 숫자는 모두 tabular alignment를 우선한다.
- 숫자와 단위는 baseline 기준으로 맞춘다.
- `distance`, `time`, `pace`는 절대 줄바꿈하지 않는다.
- `km`, `/km`는 같은 줄에 유지한다.
- 긴 설명 문구보다 짧은 상태 문구를 우선한다.

## 6. Layout, Spacing, MinWidth, Z-Index

### 6.1 Spacing Tokens

| Token | Value |
|---|---|
| `space/2xs` | `4` |
| `space/xs` | `8` |
| `space/sm` | `12` |
| `space/md` | `16` |
| `space/lg` | `20` |
| `space/xl` | `24` |
| `space/2xl` | `32` |

### 6.2 Shape Tokens

| Element | Radius |
|---|---|
| chip | `12` |
| button | `16` |
| card | `18` |
| dock | `20` |
| pause control | `999` |

### 6.3 MinWidth Rules

- hero distance value block `minWidth: 160`
- hero time block `minWidth: 116`
- inline metric value line `minWidth: 72`
- top metric item `minWidth: 64`
- share footer metric cell `minWidth: 84`
- touch target minimum `44 x 44`

### 6.4 Position Rules

- 핵심 metric group는 normal flow 안에서 배치한다.
- `position: absolute`는 배경 레이어, page indicator, floating pause control, fixed bottom dock에만 제한한다.
- absolute 요소는 safe area inset을 계산한 shell 안에서만 배치한다.
- absolute 요소가 텍스트 흐름을 가리면 설계 실패로 간주한다.

### 6.5 Z-Index Rules

| Layer | zIndex |
|---|---|
| background image / map | `0` |
| blur / dark scrim | `10` |
| page content base | `20` |
| top metric bar | `30` |
| hero metric block | `40` |
| page indicator | `50` |
| bottom dock | `60` |
| pause control | `70` |
| modal / share sheet | `100+` |

## 7. Metric Number Rules

BeamChaser의 가장 중요한 컴포넌트는 metric line이다.

강제 규칙:
- primary metric은 opacity `1.0`
- distance/time/pace는 절대 줄바꿈 금지
- `km`, `/km`는 반드시 같은 줄 유지
- 숫자와 단위는 baseline align
- 단위는 숫자보다 작지만 너무 옅지 않게 유지
- `--:--`, `0.00`, `01:43`도 실제 값과 동일한 공간 규칙을 따라야 한다

표현 규칙:
- 거리: `0.00 km`
- 페이스: `04:32 /km`
- 시간: `01:43`
- 케이던스: `176 spm`

구현 규칙:
- iOS는 `RBMetricLine` 또는 동일 역할의 단일 컴포넌트로만 표현한다.
- React Native / Expo는 `Text`를 여러 개 흩어 놓지 말고 한 컨테이너 안에서 `flexDirection: 'row'`, `alignItems: 'baseline'`, `flexWrap: 'nowrap'`를 강제한다.
- 자동 축소가 필요하면 전체 block을 줄이고 unit만 따로 줄이지 않는다.

## 8. Safe Area Rules

강제 규칙:
- Dynamic Island와 status bar safe area를 침범하지 말 것
- 하단 home indicator 영역과 제스처 영역을 침범하지 말 것
- top controls는 safe area top + `12 ~ 16` 아래에 시작할 것
- bottom dock height는 `88 ~ 104px`
- bottom dock 내부 버튼은 safe area bottom inset을 포함해 시각적으로 밀리지 않게 정렬할 것

세부 규칙:
- top metric bar 시작점은 `safeAreaTop + 12` 이상
- segmented control, page switcher, status chip은 status bar와 겹치지 않는다
- hero metric은 Dynamic Island 하단에서 최소 `24` 떨어진 위치에서 시작한다
- bottom dock은 `safeAreaBottom + 12`의 바깥 여백을 확보한다
- full-screen blur 또는 map 배경은 safe area를 덮어도 되지만, interactive content는 safe area 안에만 놓는다

## 9. Running Screen Layout

BeamChaser 러닝 화면은 다음 4개 계층으로 설계한다.

### 9.1 Top Metric Bar

- 배경: solid 또는 `70%` 이상 불투명 surface
- 포함 정보: 현재 페이스, 심박 또는 GPS, 레이저 갭, 상태 dot
- height: `44 ~ 56`
- 라벨보다 값이 먼저 읽혀야 한다
- divider 남발보다 spacing으로 구분한다

### 9.2 Hero Metric Block

- 우선순위: 거리 > 시간 > 현재 페이스
- hero metric은 화면 중앙 또는 상단 1/3 지점에 배치한다
- `0.00 km`와 `01:43`은 서로 시각적 무게가 맞아야 한다
- shadow는 얕게 허용하지만 blur에 의존한 판독성 보정은 금지한다

### 9.3 Page Content Region

- map page, music page, metrics page는 동일한 safe-area shell 안에서 전환한다
- 각 페이지는 bottom dock를 침범하지 않도록 하단 reserved area를 확보한다
- 좌우 split layout은 모바일에서 금지한다

### 9.4 Bottom Dock

- height: `88 ~ 104px`
- 배경: `bg/solidStrong` 또는 동등한 고대비 surface
- dock은 항상 하나의 시각적 plane으로 보여야 한다
- pause, previous, next, page switch, secondary control은 dock 기준선에 정렬한다

## 10. Music Background Overlay Rule

음악 페이지는 분위기를 줄 수 있지만 정보가 사라지면 안 된다.

강제 규칙:
- 배경 이미지 또는 blur 위에는 반드시 black overlay `0.45 ~ 0.65`
- 텍스트는 overlay 위에 놓고 `text/primary` 또는 대비 기준을 만족하는 색만 사용
- 앨범 아트는 선명하게 유지하되 주변 배경은 정보보다 뒤로 물러나야 한다

구성 규칙:
- 배경 레이어: 앨범 아트 확대본 또는 흐린 background
- overlay 레이어: `overlay/black55` 기본, 필요한 경우 `overlay/black65`
- content 레이어: top metric bar, hero metric, album art card, bottom dock
- blur는 분위기용이며 contrast 해결 수단이 아니다

금지:
- blur만 깔고 흰 텍스트를 올리는 방식
- 텍스트 뒤에서 밝은 이미지 하이라이트가 지나가는 상태
- album art 주변에 과한 glow 추가

## 11. Map Page Rule

- map은 정보 배경이어야 하며 metric과 control이 우선이다
- 지도 위에 텍스트를 직접 얹을 때도 solid plate 또는 dark scrim을 사용한다
- route, current location, pace zone만 강조하고 장식성 색상은 쓰지 않는다
- bottom metric chrome은 지도 내부 padding으로 해결하지 말고 dock layer에 속하게 한다
- 지도 상단 컨트롤은 safe area 안에서 정렬한다

지도 상태 표현:
- fast: `map/fast`
- steady: `map/steady`
- slow: `map/slow`
- 현재 위치: 고대비 white core + brand/orange ring 또는 system location style

## 12. Pause Control Rule

pause control은 배경 위에 녹아들면 안 된다.

강제 규칙:
- pause button size `72 ~ 84px`
- touch target 최소 `44px`, 실제 시각 크기는 `72px` 이상 권장
- pause control은 dock 또는 명확한 floating plate 위에 배치한다
- 버튼 뒤 배경과 동일 밝기대에 놓지 않는다

시각 규칙:
- running 상태: 오렌지 filled 원형 버튼
- paused 상태: resume primary, finish secondary 또는 destructive 조합
- icon은 중앙 정렬, 배경 대비 `7:1` 이상 유지
- pause control에 drop shadow를 쓰더라도 contrast를 대신할 수 없다

금지:
- blur 배경 위에 바로 오렌지 버튼만 놓기
- 버튼 주변에 아무 받침 plane 없이 단독 부유시키기
- previous/next 버튼이 화면 가장자리에서 잘리는 배치

## 13. Share Card Rule

share card는 BeamChaser의 기록 요약 카드다. 포스터가 아니라 기록 카드여야 한다.

구조:
- 상단: 브랜드, 날짜, 러닝 타이틀
- 중단: route 또는 대표 이미지
- 하단: metric footer

규칙:
- card radius `18`
- footer는 distance / time / pace 3분할 우선
- footer metric은 `minWidth: 84` 이상
- start / end marker, km marker, pace route variant를 지원한다
- 배경 사진 variant를 허용하더라도 metric footer는 solid 또는 고대비 overlay 위에 올린다
- 공유 카드에서 설명 문구를 길게 붙이지 않는다

## 14. Accessibility Contrast Rule

강제 규칙:
- critical metric contrast `7:1` 이상
- 일반 텍스트 `4.5:1` 이상
- 단위, 캡션, 상태 보조 텍스트도 배경 위에서 판독 가능해야 한다
- blur, image, gradient가 있는 경우 대비 측정 기준은 최종 overlay 합성 결과로 판단한다

검증 규칙:
- white text on raw blur는 실패로 간주한다
- orange text on translucent warm background는 대비를 다시 계산한다
- disabled state라도 정보성 텍스트는 `4.5:1` 미만으로 떨어뜨리지 않는다

## 15. React Native / Expo Component Rules

RunBeamAndroid와 향후 Expo 전환을 모두 고려한 규칙이다.

### 15.1 Required Component Boundaries

- `RunningSafeAreaShell`: safe area inset 계산, top/bottom reserved area 제공
- `TopMetricBar`: solid background, metric no-wrap, state chip 포함
- `MetricValueLine`: 숫자 + 단위 한 줄 고정
- `HeroMetricBlock`: distance, time, pace 중심 배치
- `MusicBackgroundOverlay`: image/blur + black overlay `0.45 ~ 0.65`
- `MapPageChrome`: map 위 metric plate와 control plane 관리
- `BottomControlDock`: height `88 ~ 104`, zIndex `60`
- `PauseControl`: size `72 ~ 84`, 고정 contrast 보장
- `ShareMetricFooter`: 3-column or 2-column responsive footer

### 15.2 React Native Style Rules

- `flexWrap: 'nowrap'`를 metric line 기본값으로 사용한다
- `alignItems: 'baseline'`로 숫자와 단위를 정렬한다
- `fontVariant: ['tabular-nums']`를 우선 적용한다
- `minWidth` 토큰을 style object에 명시한다
- `position: 'absolute'`는 safe-area shell 내부로 제한한다
- `zIndex`는 토큰으로 관리하고 매직 넘버를 흩뿌리지 않는다
- `BlurView`를 쓸 경우에도 overlay black layer를 따로 추가한다
- `StatusBar.currentHeight`, safe area inset, bottom gesture inset을 동시에 고려한다

### 15.3 React Native / Expo Anti-Patterns

- CSS web 속성 사고방식을 그대로 가져오지 않는다
- `vh`, `vw`, `position: sticky`, hover 상태, CSS backdrop filter 전제를 쓰지 않는다
- hero section 비율을 픽셀 고정으로 두지 않는다
- background art 위에 raw text를 직접 올리지 않는다

### 15.4 Implementation Example

```tsx
type MetricValueLineProps = {
  value: string;
  unit?: string;
  tone?: 'primary' | 'secondary';
  size?: 'hero' | 'secondary';
};

type BottomControlDockProps = {
  safeBottom: number;
  leftAction?: React.ReactNode;
  centerAction: React.ReactNode;
  rightAction?: React.ReactNode;
};
```

```tsx
const styles = StyleSheet.create({
  metricLine: {
    flexDirection: 'row',
    flexWrap: 'nowrap',
    alignItems: 'baseline',
    minWidth: 72,
  },
  dock: {
    position: 'absolute',
    left: 16,
    right: 16,
    bottom: 12,
    minHeight: 88,
    maxHeight: 104,
    zIndex: 60,
  },
});
```

## 16. Do / Don't Examples

### Do

- 거리와 단위를 `0.00 km` 한 줄로 유지한다
- top metric bar에 solid dark plate를 사용한다
- 앨범 아트 배경 위에 `overlay/black55`를 먼저 깐다
- pause control을 dock plane 위에 올려 배경과 분리한다
- page switcher와 status chip을 safe area 아래로 내린다

### Don't

- blur background 위에 overlay 없이 흰 텍스트를 올리지 않는다
- 거리 수치와 `km`를 줄바꿈하거나 별도 column으로 분리하지 않는다
- pause 버튼을 배경 위에 그냥 띄우지 않는다
- Dynamic Island 바로 아래에 segmented control을 밀어 넣지 않는다
- 웹 hero 카드처럼 좌우 split layout을 모바일 러닝 화면에 넣지 않는다

## 17. Broken UI 방지 체크리스트

배포 전 반드시 확인한다.

- smallest iPhone에서 top controls가 Dynamic Island와 status bar를 침범하지 않는가
- bottom dock height가 `88 ~ 104px` 범위 안에 있는가
- pause button이 `72 ~ 84px` 크기를 유지하는가
- previous/next/pause가 좌우 화면 밖으로 잘리지 않는가
- critical metric contrast가 `7:1` 이상인가
- 일반 텍스트 contrast가 `4.5:1` 이상인가
- blur/image background 위 텍스트에 black overlay `0.45 ~ 0.65`가 실제로 들어갔는가
- distance/time/pace가 어떤 상태에서도 줄바꿈되지 않는가
- `km`, `/km`, `spm`, `bpm`가 값과 같은 줄에 있는가
- metric number와 unit baseline이 맞는가
- top metric bar 배경 불투명도가 `70%` 이상인가
- zIndex 충돌로 dock, page indicator, modal이 서로 가리지 않는가
- absolute positioning이 텍스트 레이아웃을 깨뜨리지 않는가
- 모바일 앱에 hover, desktop width, landing hero 토큰이 남아 있지 않은가
- share footer 1개, 2개, 3개 metric 조합이 모두 깨지지 않는가

## 18. Current Screen Problem Analysis

현재 러닝 화면 기준 문제는 다음과 같다.

### 18.1 Blur Background 위 텍스트 가독성 저하

- 배경 blur만 있고 black overlay가 충분하지 않아 숫자와 보조 텍스트가 묻힌다.
- 특히 상단 컨트롤, 대형 거리 수치, 음악 카드 주변 텍스트가 밝은 배경 영역과 섞인다.

### 18.2 Pause Control이 배경과 섞임

- pause 버튼은 오렌지지만 받쳐주는 dock plane이 약하다.
- 주변 컨트롤이 하단 가장자리로 밀려 화면 바깥으로 잘리는 인상이 생긴다.

### 18.3 Safe Area / Dynamic Island 침범 위험

- 상단 segmented control이 너무 위에 있다.
- 러닝 중 상단 control cluster는 Dynamic Island 하단 여백이 부족해 보인다.

### 18.4 숫자와 단위 정렬 파손

- distance, time, pace가 각각 다른 텍스트 스타일과 위치 규칙으로 그려져 baseline 통일감이 없다.
- `km`, `/km` 단위는 보조 텍스트 취급을 하더라도 동일 줄 고정 컴포넌트로 관리해야 한다.

### 18.5 웹 스타일 토큰 잔재

- 좌우가 빈 split card 느낌, 큰 blur panel, floating orb 같은 웹형 장식이 모바일 러닝 정보 구조를 약화시킨다.
- 러닝 화면은 프로모션 hero가 아니라 계기판이므로 정보 plane이 더 강해야 한다.

### 18.6 규칙 부재로 인한 재발 가능성

- contrast, minWidth, zIndex, position rule이 명문화되지 않아 같은 문제가 반복된다.
- 이번 문서에서 해당 규칙을 토큰 수준으로 고정해야 재발을 막을 수 있다.

## 19. Cursor / Codex Implementation Prompt

아래 프롬프트를 그대로 사용해도 된다.

```md
BeamChaser의 러닝 화면을 DESIGN.md 기준으로 수정하라.

필수 규칙:
- 모바일 앱 기준으로만 설계할 것. 웹/랜딩페이지 스타일 금지.
- 배경 이미지 또는 blur 위에는 반드시 black overlay 0.45~0.65를 적용할 것.
- primary metric은 opacity 1.0을 유지할 것.
- distance/time/pace는 절대 줄바꿈하지 말 것.
- km, /km는 같은 줄에 유지할 것.
- 숫자와 단위는 baseline align으로 맞출 것.
- pause button은 72~84px.
- bottom dock height는 88~104px.
- Dynamic Island와 status bar safe area를 침범하지 말 것.
- touch target은 최소 44px.
- critical metric contrast는 7:1 이상.
- 일반 텍스트는 4.5:1 이상.
- top metric bar는 solid 또는 70% 이상 불투명 배경.
- minWidth, zIndex, position rule을 명시적으로 적용할 것.

구현 요구:
- React Native / Expo 또는 SwiftUI에서 metric number를 단일 reusable component로 만들 것.
- top metric bar, hero metric block, bottom dock, pause control을 분리된 컴포넌트로 정리할 것.
- map page, music page, metrics page 모두 동일한 safe-area shell 안에서 동작하게 만들 것.
- dock 바깥에 떠 있는 컨트롤 때문에 잘림이 생기지 않게 할 것.

출력 요구:
- 수정한 컴포넌트 구조 설명
- 적용한 토큰 설명
- 어떤 contrast / safe area 문제를 해결했는지 요약
- smallest iPhone 기준으로 깨지지 않도록 한 검증 포인트 설명
```