import SwiftUI

struct RunnerPOVView: View {
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var locationService: LocationService
    
    // 애니메이션용 상태
    @State private var roadOffset: CGFloat = 0
    private let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // 1. 배경 (어두운 아스팔트 느낌)
            Color(white: 0.1).ignoresSafeArea()
            
            // 2. 원근감이 적용된 도로
            GeometryReader { geo in
                ZStack {
                    // 도로 본체
                    Path { path in
                        path.move(to: CGPoint(x: geo.size.width * 0.2, y: geo.size.height))
                        path.addLine(to: CGPoint(x: geo.size.width * 0.45, y: geo.size.height * 0.4))
                        path.addLine(to: CGPoint(x: geo.size.width * 0.55, y: geo.size.height * 0.4))
                        path.addLine(to: CGPoint(x: geo.size.width * 0.8, y: geo.size.height))
                    }
                    .fill(Color(white: 0.15))
                    
                    // 움직이는 중앙 점선 (속도 반영)
                    ForEach(0..<5) { i in
                        let yPos = (roadOffset + CGFloat(i) * 100).truncatingRemainder(dividingBy: 500)
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 4, height: 40)
                            .scaleEffect(yPos / 500) // 멀어질수록 작아짐
                            .position(x: geo.size.width / 2, y: yPos + geo.size.height * 0.4)
                    }
                }
            }
            .mask(Rectangle()) // 도로 영역 제한
            
            // 3. 레이저 포인트 (지면에 맺히는 점)
            VStack {
                Spacer()
                
                let pitch = Double(bleService.currentPitch)
                let servo = Double(bleService.servoAngle)
                
                // 보정 로직 시뮬레이션: 각도에 따라 지면에서의 거리(y) 조절
                // 서보 각도가 85도일 때가 기준(약 3m 앞)
                let angleAdjustment = (servo - 85) - pitch
                let laserYOffset = CGFloat(angleAdjustment * 5)
                
                LaserDot(size: 20, glowRadius: 15)
                    .foregroundStyle(zoneColor)
                    .offset(y: -150 + laserYOffset) // 기본 150px 위치에서 각도에 따라 이동
                    .shadow(color: zoneColor, radius: 20)
                    .animation(.interpolatingSpring(stiffness: 100, damping: 10), value: laserYOffset)
                
                Spacer().frame(height: 100)
            }
            
            // 4. 상단 정보 오버레이
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("SIMULATED SPEED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                        Text(String(format: "%.1f km/h", locationService.currentSpeed * 3.6))
                            .font(RBFont.metric(24))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("GIMBAL STATUS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                        Text(bleService.sensitivity > 0 ? "ACTIVE" : "STANDBY")
                            .font(RBFont.label(14))
                            .foregroundStyle(bleService.sensitivity > 0 ? .green : .orange)
                    }
                }
                .padding(20)
                .background(.black.opacity(0.5))
                Spacer()
            }
        }
        .onReceive(timer) { _ in
            // 속도에 비례하여 도로 애니메이션 속도 조절
            let speed = locationService.currentSpeed > 0 ? locationService.currentSpeed : 2.0 // 최소 이동감
            roadOffset += CGFloat(speed * 2)
        }
    }
    
    private var zoneColor: Color {
        switch bleService.deviceZone {
        case .blue: return .blue
        case .green: return .green
        case .red: return .red
        default: return .green
        }
    }
}

#Preview {
    RunnerPOVView()
        .environmentObject(MockBLEService())
        .environmentObject(LocationService())
}
