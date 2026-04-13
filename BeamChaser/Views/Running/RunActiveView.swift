import SwiftUI
import MapKit

struct RunActiveView: View {
    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var healthKit: HealthKitService
    @Environment(\.dismiss) private var dismiss

    @State private var showFinishAlert = false
    @State private var isExpanded = false  // 메트릭 패널 확장
    @State private var showGoalReachedAlert = false
    @State private var pauseBlinkOpacity: Double = 1.0
    @State private var didFinish = false
    @State private var finishedRecord: RunRecord?

    var body: some View {
        ZStack {
            // 풀스크린 지도
            RunMapView()
                .frame(minWidth: 1, minHeight: 1)
                .ignoresSafeArea()

            // 상단 오버레이 — 페이스 상태 + 레이저 갭
            if !didFinish {
                VStack(spacing: 0) {
                    topBar
                    
                    // 코칭 알림 배너
                    if let alert = runSession.coachingAlert {
                        Text(alert)
                            .font(RBFont.label(14))
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.orange.opacity(0.9))
                                    .shadow(radius: 5)
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onAppear {
                                // 4초 후 알림 숨김
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                    if runSession.coachingAlert == alert {
                                        withAnimation(.easeInOut) {
                                            runSession.coachingAlert = nil
                                        }
                                    }
                                }
                            }
                    }
                    
                    Spacer()
                }
            }

            // 종료 시 딤 오버레이
            if didFinish {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 하단 오버레이 — 메트릭 + 컨트롤
            VStack(spacing: 0) {
                Spacer()

                #if targetEnvironment(simulator)
                // 시뮬레이터 속도 표시 (키보드 방향키로 조작)
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 10))
                    Text("↑↓←→ 방향키 | Space 정지")
                        .font(RBFont.caption(10))
                    Spacer()
                    Text(String(format: "%.1f m/s", locationService.simulatorSpeed))
                        .font(RBFont.metric(14))
                        .foregroundStyle(locationService.simulatorSpeed > 0 ? RBColor.success : RBColor.textTertiary)
                }
                .foregroundStyle(RBColor.textTertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                #endif

                bottomOverlay
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(false)
        .onAppear {
            #if targetEnvironment(simulator)
            locationService.enableSimulatorMode()
            locationService.startTracking_simulator()
            #else
            locationService.startTracking()
            #endif
            // BLE 로직은 runSession.startRun() 호출 시 내부에서 처리됨
        }
        .onDisappear {
            if !didFinish {
                // 비정상 종료 — 전체 정리
                locationService.simulatorStop()
                locationService.stopTracking()
                // BLE 종료 로직은 resetSession에서 처리 가능하도록 보완 권장
                locationService.reset()
                Task { await runSession.healthKit.discardWorkout() }
            }
            // 항상 세션 초기화 (다음 러닝을 위해)
            runSession.resetSession()
        }
        .onChange(of: locationService.totalDistanceMeters) { _, newValue in
            guard runSession.runState == .running, !didFinish else { return }
            runSession.updatePace(distance: newValue)
        }
        .onChange(of: locationService.routePoints.count) { _, _ in
            guard runSession.runState == .running, !didFinish else { return }
            // 새 위치 데이터를 HealthKit 경로에 추가
            if let location = locationService.currentLocation {
                runSession.healthKit.addRouteData([location])
            }
        }
        .alert("러닝을 종료할까요?", isPresented: $showFinishAlert) {
            Button("계속 달리기", role: .cancel) {}
            Button("종료", role: .destructive) { finishRun() }
        } message: {
            Text("현재까지의 기록이 저장됩니다.")
        }
        .alert("목표 달성!", isPresented: $showGoalReachedAlert) {
            Button("계속 달리기", role: .cancel) {}
            Button("종료하기") { finishRun() }
        } message: {
            Text("설정한 목표를 달성했습니다! 계속 달릴 수도 있습니다.")
        }
        .onChange(of: runSession.goalReached) { _, reached in
            if reached {
                showGoalReachedAlert = true
            }
        }
    }

    // MARK: - 상단 바

    private var topBar: some View {
        VStack(spacing: 8) {
            // GPS 신호 + 인터벌 구간 표시
            HStack(spacing: 8) {
                gpsSignalIndicator

                if let interval = runSession.intervalProgram, !interval.segments.isEmpty {
                    let idx = min(runSession.currentIntervalIndex, interval.segments.count - 1)
                    let segment = interval.segments[idx]
                    HStack(spacing: 4) {
                        Circle()
                            .fill(intervalSegmentColor(segment))
                            .frame(width: 6, height: 6)
                        Text(segment.name)
                            .font(RBFont.label(11))
                            .foregroundStyle(.white)
                        Text(segment.formattedPace)
                            .font(RBFont.metric(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .environment(\.colorScheme, .dark)
                    .clipShape(Capsule())
                }

                Spacer()

                // 목표 진행률
                if let goal = runSession.runGoal, goal.type != .none {
                    goalProgressBadge(goal)
                }
            }

            // 페이스 상태 — 대형 배경색 변화
            paceStatusBanner

            // 레이저 갭 바 (큰 사이즈)
            laserGapBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - GPS 신호 표시

    private var gpsSignalIndicator: some View {
        let accuracy = locationService.currentLocation?.horizontalAccuracy ?? -1
        let (level, color): (String, Color) = {
            if accuracy < 0 { return ("없음", RBColor.danger) }
            if accuracy < 10 { return ("강함", RBColor.success) }
            if accuracy < 20 { return ("보통", .yellow) }
            return ("약함", RBColor.danger)
        }()
        let bars: Int = {
            if accuracy < 0 { return 0 }
            if accuracy < 10 { return 3 }
            if accuracy < 20 { return 2 }
            return 1
        }()

        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? color : Color.white.opacity(0.2))
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
            Text(level)
                .font(RBFont.caption(9))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.6))
        .environment(\.colorScheme, .dark)
        .clipShape(Capsule())
    }

    // MARK: - 목표 진행률 배지

    private func goalProgressBadge(_ goal: RunGoal) -> some View {
        let progress: Double = {
            switch goal.type {
            case .distance:
                guard let targetKm = goal.targetDistanceKm, targetKm > 0 else { return 0 }
                return min(1.0, locationService.totalDistanceMeters / 1000.0 / targetKm)
            case .time:
                guard let targetMin = goal.targetTimeMinutes, targetMin > 0 else { return 0 }
                return min(1.0, runSession.elapsedSeconds / Double(targetMin * 60))
            case .none: return 0
            }
        }()

        return HStack(spacing: 4) {
            Image(systemName: goal.type.icon)
                .font(.system(size: 10))
            Text(String(format: "%.0f%%", progress * 100))
                .font(RBFont.metric(11))
        }
        .foregroundStyle(progress >= 1.0 ? RBColor.success : RBColor.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.8))
        .environment(\.colorScheme, .dark)
        .clipShape(Capsule())
    }

    // MARK: - 페이스 상태 배너 (대형 + 배경색 변화)

    private var paceStatusBanner: some View {
        let status = runSession.paceMaker.paceStatus
        let bgColor = paceStatusColor

        return HStack(spacing: 12) {
            // 상태 아이콘 (큰 사이즈)
            Image(systemName: status.icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.label)
                    .font(RBFont.label(14))
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
            }

            Spacer()

            // 레이저 갭 (큰 숫자)
            HStack(spacing: 6) {
                LaserDot(size: 12, glowRadius: 8)
                Text(runSession.paceMaker.formattedGap)
                    .font(RBFont.metric(28))
                    .foregroundStyle(.white)
                    .fontWeight(.heavy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(bgColor.opacity(0.85))
        )
        .shadow(color: bgColor.opacity(0.4), radius: 8, y: 2)
    }

    // MARK: - 레이저 갭 바 (미니)

    private var laserGapBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let gap = runSession.paceMaker.gapMeters
            let maxGap: Double = 100
            let normalizedGap = max(-1.0, min(1.0, gap / maxGap))
            let centerX = width / 2.0
            let halfWidth = width / 2.0 - 12.0
            let offsetX = normalizedGap * halfWidth

            ZStack {
                // 배경
                Capsule()
                    .fill(.black.opacity(0.4))
                    .frame(height: 6)

                // 센터 (목표 위치)
                Circle()
                    .fill(RBColor.accent)
                    .frame(width: 8, height: 8)
                    .position(x: centerX, y: 3)

                // 현재 위치
                LaserDot(size: 12, glowRadius: 8)
                    .position(x: centerX + offsetX, y: 3)
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 4)
    }

    private var paceStatusColor: Color {
        switch runSession.paceMaker.paceStatus {
        case .ahead: return RBColor.success
        case .onPace: return RBColor.accent
        case .behind: return RBColor.danger
        }
    }

    private func intervalSegmentColor(_ segment: IntervalSegment) -> Color {
        let pace = segment.totalSecondsPerKm
        if pace < 270 { return RBColor.danger }       // < 4:30
        if pace < 330 { return RBColor.accent }        // < 5:30
        return RBColor.success
    }

    // MARK: - 하단 오버레이

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            if !didFinish {
                // 탭하여 확장/축소
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                }

                if isExpanded {
                    expandedMetrics
                } else {
                    compactMetrics
                }
            }

            // 컨트롤 버튼
            controlButtons
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: -5)
    }

    // MARK: - 간결 메트릭 (기본)

    private var compactMetrics: some View {
        HStack(spacing: 0) {
            MetricView(
                label: "거리",
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                valueSize: 32
            )
            .frame(maxWidth: .infinity)

            // 구분선
            Rectangle()
                .fill(RBColor.divider)
                .frame(width: 1, height: 40)

            MetricView(
                label: "시간",
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: "",
                valueSize: 32
            )
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(RBColor.divider)
                .frame(width: 1, height: 40)

            MetricView(
                label: "페이스",
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km",
                valueSize: 32
            )
            .frame(maxWidth: .infinity)

            // 심박수 (워치 연동 시)
            if healthKit.currentHeartRate > 0 {
                Rectangle()
                    .fill(RBColor.divider)
                    .frame(width: 1, height: 40)

                MetricView(
                    label: "심박수",
                    value: String(format: "%.0f", healthKit.currentHeartRate),
                    unit: "bpm",
                    valueSize: 32
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 확장 메트릭

    private var expandedMetrics: some View {
        VStack(spacing: 16) {
            // 거리 (대형)
            VStack(spacing: 2) {
                Text("거리".uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textSecondary)
                    .tracking(1.2)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", locationService.totalDistanceMeters / 1000.0))
                        .font(RBFont.metric(56))
                        .foregroundStyle(.white)
                    Text("km")
                        .font(RBFont.label(18))
                        .foregroundStyle(RBColor.textSecondary)
                }
            }

            // 시간 + 페이스 + 목표
            HStack(spacing: 0) {
                MetricView(
                    label: "시간",
                    value: RunRecord.formatDuration(runSession.elapsedSeconds),
                    unit: ""
                )
                .frame(maxWidth: .infinity)

                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)

                MetricView(
                    label: "현재 페이스",
                    value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                    unit: "/km"
                )
                .frame(maxWidth: .infinity)

                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)

                if let target = runSession.paceMaker.target {
                    MetricView(label: "목표", value: target.formatted, unit: "")
                        .frame(maxWidth: .infinity)
                } else {
                    MetricView(label: "속도", value: String(format: "%.1f", locationService.currentSpeed * 3.6), unit: "km/h")
                        .frame(maxWidth: .infinity)
                }
            }

            // 갭 상세
            HStack {
                HStack(spacing: 6) {
                    LaserDot(size: 8, glowRadius: 4)
                    Text("레이저 갭")
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textSecondary)
                }
                Spacer()
                Text(runSession.paceMaker.formattedGap)
                    .font(RBFont.metric(16))
                    .foregroundStyle(paceStatusColor)
                Text(runSession.paceMaker.formattedTimeGap)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
            }
            .padding(.horizontal, 4)

            // 심박수 + 칼로리 (워치 연동 시)
            if healthKit.currentHeartRate > 0 {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                        Text("심박수")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f bpm", healthKit.currentHeartRate))
                        .font(RBFont.metric(16))
                        .foregroundStyle(.red)
                    if healthKit.activeCalories > 0 {
                        Text(String(format: "%.0f kcal", healthKit.activeCalories))
                            .font(RBFont.caption(12))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                }
                .padding(.horizontal, 4)
            }

            // 워치/폰 운동 앱 페이스 (HealthKit runningSpeed)
            if healthKit.currentRunningPace > 0 {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 10))
                            .foregroundStyle(RBColor.accent)
                        Text("워치 페이스")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                    Spacer()
                    Text(RunRecord.formatPace(healthKit.currentRunningPace))
                        .font(RBFont.metric(16))
                        .foregroundStyle(RBColor.accent)
                    Text("/km")
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - 컨트롤 버튼

    private var controlButtons: some View {
        Group {
            if didFinish {
                finishedControlButtons
            } else if runSession.runState == .paused {
                pausedControlButtons
            } else {
                runningControlButtons
            }
        }
    }

    // 러닝 중: 좌측 잠금, 중앙 일시정지 (크게)
    private var runningControlButtons: some View {
        HStack(spacing: 24) {
            // 잠금 (화면 고정용 placeholder)
            Button {
                // 화면 잠금 기능 (향후)
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(RBColor.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(RBColor.cardBg)
                    .clipShape(Circle())
            }

            // 일시정지 (메인 버튼)
            Button {
                runSession.pauseRun()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(RBColor.accentGradient)
                    .clipShape(Circle())
                    .shadow(color: RBColor.accent.opacity(0.4), radius: 12, y: 4)
            }

            // 빈 공간 (대칭용)
            Color.clear
                .frame(width: 52, height: 52)
        }
    }

    // 일시정지 중: 좌측 종료(빨강), 중앙 상태 텍스트, 우측 재개(초록) — 슬라이드 느낌
    private var pausedControlButtons: some View {
        VStack(spacing: 16) {
            // 일시정지 상태 표시
            HStack(spacing: 6) {
                Circle()
                    .fill(RBColor.accent)
                    .frame(width: 8, height: 8)
                    .opacity(pauseBlinkOpacity)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pauseBlinkOpacity)
                Text("일시정지")
                    .font(RBFont.label(14))
                    .foregroundStyle(RBColor.textSecondary)
            }
            .onAppear { pauseBlinkOpacity = 0.3 }
            .onDisappear { pauseBlinkOpacity = 1.0 }

            HStack(spacing: 20) {
                // 종료 버튼 (좌측, 빨강, 크게)
                Button {
                    showFinishAlert = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(RBColor.danger)
                            .clipShape(Circle())
                        Text("종료")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.danger)
                    }
                }

                // 재개 버튼 (우측, 초록, 크게)
                Button {
                    runSession.resumeRun()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(
                                LinearGradient(
                                    colors: [RBColor.success, RBColor.success.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: RBColor.success.opacity(0.4), radius: 12, y: 4)
                        Text("계속 달리기")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.success)
                    }
                }
            }
        }
    }

    // 러닝 완료 — 요약 + 완료 버튼

    private var finishedControlButtons: some View {
        VStack(spacing: 16) {
            if let record = finishedRecord {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(RBColor.success)
                        Text("러닝 완료")
                            .font(RBFont.label(18))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 24) {
                        VStack(spacing: 4) {
                            Text(record.formattedDistance)
                                .font(RBFont.metric(22))
                                .foregroundStyle(.white)
                            Text("거리")
                                .font(RBFont.caption(10))
                                .foregroundStyle(RBColor.textSecondary)
                        }
                        VStack(spacing: 4) {
                            Text(record.formattedDuration)
                                .font(RBFont.metric(22))
                                .foregroundStyle(.white)
                            Text("시간")
                                .font(RBFont.caption(10))
                                .foregroundStyle(RBColor.textSecondary)
                        }
                        VStack(spacing: 4) {
                            Text(record.formattedPace)
                                .font(RBFont.metric(22))
                                .foregroundStyle(.white)
                            Text("페이스")
                                .font(RBFont.caption(10))
                                .foregroundStyle(RBColor.textSecondary)
                        }
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                    Text("완료")
                        .font(RBFont.label(17))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RBColor.accentGradient)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Actions

    private func finishRun() {
        guard !didFinish else { return }
        didFinish = true
        // 1. 시뮬레이터 이동 중지
        locationService.simulatorStop()
        // 2. 기록 캡처 (reset 전에 값 복사)
        let routePoints = locationService.routePoints
        let totalDistance = locationService.totalDistanceMeters
        // 3. 기록 저장 + HealthKit 운동 종료
        runSession.finishRun(
            routePoints: routePoints,
            totalDistance: totalDistance
        )
        // 4. 완료 기록 캡처 (UI 표시용)
        finishedRecord = runSession.currentRecord
        // 5. 위치 추적 중지
        locationService.stopTracking()
        // 6. 위치 데이터 초기화
        locationService.reset()
        // dismiss는 사용자가 "완료" 버튼을 누를 때 실행
    }


}

#Preview {
    NavigationStack {
        RunActiveView()
            .environmentObject(RunSessionManager())
            .environmentObject(LocationService())
            .environmentObject(BLEService())
            .environmentObject(HealthKitService())
    }
}
