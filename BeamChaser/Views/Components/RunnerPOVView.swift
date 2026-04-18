import SwiftUI

struct RunnerPOVView: View {
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var runSession: RunSessionManager
    
    // 시뮬레이터 속도 조절용 (km/h 단위로 UI 표시)
    @State private var mySpeedKmh: Double = 10.0
    @State private var targetPaceMin: Int = 6
    @State private var targetPaceSec: Int = 0
    
    // 도로 애니메이션 상태
    @State private var roadOffset: CGFloat = 0
    private let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // 1. POV 시뮬레이션 영역
            ZStack {
                // 아스팔트 배경
                Color(white: 0.05).ignoresSafeArea()
                
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let vanishingPoint = CGPoint(x: w/2, y: h * 0.3)
                    
                    // A. 도로 원근감 (Trapezoid)
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.48, y: vanishingPoint.y))
                        path.addLine(to: CGPoint(x: w * 0.52, y: vanishingPoint.y))
                        path.addLine(to: CGPoint(x: w * 1.2, y: h))
                        path.addLine(to: CGPoint(x: w * -0.2, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(colors: [Color(white: 0.1), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)
                    )
                    
                    // B. 움직이는 중앙 점선
                    ZStack {
                        ForEach(0..<8) { i in
                            let progress = (roadOffset + CGFloat(i) * 60).truncatingRemainder(dividingBy: 480) / 480
                            let currentY = vanishingPoint.y + (h - vanishingPoint.y) * progress
                            let lineW = 4.0 * progress + 1.0
                            let lineH = 40.0 * progress + 5.0
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: lineW, height: lineH)
                                .position(x: w/2, y: currentY)
                        }
                    }
                    
                    // C. 도로 옆 경계선
                    Path { path in
                        path.move(to: vanishingPoint)
                        path.addLine(to: CGPoint(x: w * -0.1, y: h))
                        path.move(to: vanishingPoint)
                        path.addLine(to: CGPoint(x: w * 1.1, y: h))
                    }
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                }
                
                // D. 레이저 포인트 (물리 엔진 기반)
                VStack {
                    Spacer()
                    
                    // 갭(m)에 따른 위치 계산
                    // gapMeters: 양수면 내가 앞섬(레이저는 내 뒤/화면 아래), 음수면 레이저가 앞섬(화면 위)
                    let gap = runSession.paceMaker.gapMeters
                    let pitch = Double(bleService.currentPitch)
                    let servo = Double(bleService.servoAngle)
                    
                    // 기본 위치 (3m 앞) + 갭 반영 + 짐벌 보정 미세 반영
                    // 1m당 약 40px 이동 시뮬레이션
                    let basePos: CGFloat = -180 
                    let gapAdjustment = CGFloat(gap * 40)
                    let gimbalAdjustment = CGFloat((servo - 85 - pitch) * 3)
                    
                    let isLaserOn = bleService.deviceStatus?.isLaserActive ?? true
                    
                    if isLaserOn {
                        LaserDot(size: 24, glowRadius: 18)
                            .foregroundStyle(zoneColor)
                            .offset(y: basePos - gapAdjustment + gimbalAdjustment)
                            .shadow(color: zoneColor, radius: 25)
                            .animation(.interpolatingSpring(stiffness: 50, damping: 15), value: gap)
                    }
                    
                    Spacer().frame(height: 120)
                }
                
                // 안내 텍스트
                if !locationService.isTracking {
                    Text("시뮬레이션을 시작하려면\n아래 '내 속도'를 높이세요")
                        .font(RBFont.label(14))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20).stroke(RBColor.divider, lineWidth: 1)
            )
            
            // 2. 실험실 제어 패널
            VStack(spacing: 16) {
                // 내 속도 조절
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("내 러닝 속도", systemImage: "figure.run")
                            .font(RBFont.label(13))
                        Spacer()
                        Text(String(format: "%.1f km/h", mySpeedKmh))
                            .font(RBFont.metric(16))
                            .foregroundStyle(RBColor.accent)
                    }
                    Slider(value: $mySpeedKmh, in: 0...20, step: 0.5)
                        .tint(RBColor.accent)
                        .onChange(of: mySpeedKmh) { _, newValue in
                            updateSimulatedSpeed(newValue)
                        }
                }
                
                Divider().overlay(RBColor.divider)
                
                // 레이저 페이스 조절
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("레이저 목표 페이스", systemImage: "bolt.fill")
                            .font(RBFont.label(13))
                        Spacer()
                        Text("\(targetPaceMin)'\(String(format: "%02d", targetPaceSec))\" /km")
                            .font(RBFont.metric(16))
                            .foregroundStyle(.green)
                    }
                    HStack(spacing: 12) {
                        Stepper("분: \(targetPaceMin)", value: $targetPaceMin, in: 3...12)
                        Stepper("초: \(targetPaceSec)", value: $targetPaceSec, in: 0...55, step: 5)
                    }
                    .font(RBFont.caption(12))
                    .onChange(of: targetPaceMin) { updateTargetPace() }
                    .onChange(of: targetPaceSec) { updateTargetPace() }
                }
                
                // 갭 정보 요약
                HStack {
                    VStack(alignment: .leading) {
                        Text("거리 차이(GAP)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.gray)
                        Text(runSession.paceMaker.formattedGap)
                            .font(RBFont.metric(22))
                            .foregroundStyle(zoneColor)
                    }
                    Spacer()
                    if runSession.paceMaker.gapMeters > 0 {
                        Text("레이저보다 빠름")
                            .font(RBFont.caption(11))
                            .foregroundStyle(.blue)
                    } else {
                        Text("레이저를 따라가세요")
                            .font(RBFont.caption(11))
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
            .background(RBColor.cardBg)
        }
        .onAppear {
            setupInitialValues()
        }
        .onReceive(timer) { _ in
            let speed = locationService.currentSpeed
            roadOffset += CGFloat(speed * 3) // 속도에 따라 도로 흐름 속도 조절
            
            // 시뮬레이터 모드일 때 매 프레임마다 거리 업데이트 강제 트리거
            if locationService.isSimulatorMode {
                runSession.updatePace(distance: locationService.totalDistanceMeters)
            }
        }
    }
    
    private var zoneColor: Color {
        let gap = runSession.paceMaker.gapMeters
        if gap > 5 { return .blue }
        if gap < -5 { return .red }
        return .green
    }
    
    private func setupInitialValues() {
        if let target = runSession.paceMaker.target {
            targetPaceMin = target.minutesPerKm
            targetPaceSec = target.secondsPerKm
        }
        mySpeedKmh = locationService.currentSpeed * 3.6
    }
    
    private func updateSimulatedSpeed(_ kmh: Double) {
        if !locationService.isTracking {
            locationService.startTracking_simulator()
        }
        locationService.setSimulatorSpeedKmh(kmh)
    }
    
    private func updateTargetPace() {
        let target = PaceTarget(minutesPerKm: targetPaceMin, secondsPerKm: targetPaceSec)
        runSession.paceMaker.start(target: target)
    }
}

#Preview {
    RunnerPOVView()
        .environmentObject(MockBLEService())
        .environmentObject(LocationService())
        .environmentObject(RunSessionManager())
}
