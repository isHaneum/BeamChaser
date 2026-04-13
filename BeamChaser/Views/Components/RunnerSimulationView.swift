import SwiftUI

struct RunnerSimulationView: View {
    @EnvironmentObject var bleService: BLEService
    
    // 애니메이션용 상하 바운스
    @State private var verticalOffset: CGFloat = 0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 1. 배경 (공간감)
                LinearGradient(colors: [Color.black.opacity(0.8), Color.gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                // 2. 가상 지면
                VStack {
                    Spacer(minLength: 250)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .overlay(
                            // 지면의 거리 눈금
                            HStack(spacing: 50) {
                                ForEach(0..<10) { i in
                                    VStack {
                                        Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 10)
                                        Text("\(i)m").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
                                    }
                                }
                            }
                        )
                    Spacer()
                }

                // 3. 러너 시뮬레이션 그룹
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        // A. 레이저 광선 (상체에서 지면으로)
                        LaserBeamView(pitch: Double(bleService.currentPitch), servoAngle: Double(bleService.servoAngle))
                            .offset(y: 40)

                        // B. 상체 모델 (Vest)
                        VStack(spacing: 0) {
                            // 머리
                            Circle()
                                .fill(RBColor.textPrimary)
                                .frame(width: 20, height: 20)
                            
                            // 몸체 (조끼 장착 부위)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(RBColor.accentGradient)
                                .frame(width: 40, height: 60)
                                .overlay(
                                    VStack {
                                        Circle().fill(.white).frame(width: 4, height: 4) // 레이저 렌즈 위치
                                        Spacer()
                                    }.padding(8)
                                )
                        }
                        .rotation3DEffect(.degrees(Double(bleService.currentPitch)), axis: (x: 1, y: 0, z: 0))
                        .offset(y: verticalOffset) // 달리기 바운스
                    }
                    Spacer()
                }
                .padding(.top, 100)
            }
            .frame(height: 400)
            
            // 4. 하단 제어 및 상태 정보
            VStack(spacing: 12) {
                HStack {
                    statusItem(label: "몸 기울기", value: "\(bleService.currentPitch)°", color: .orange)
                    Spacer()
                    statusItem(label: "서보 각도", value: "\(bleService.servoAngle)°", color: .blue)
                    Spacer()
                    statusItem(label: "짐벌 감도", value: "\(bleService.sensitivity)", color: .green)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(RBColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(16)
        }
        .onReceive(timer) { _ in
            // 달리기 리듬 시뮬레이션 (상하 흔들림)
            withAnimation(.easeInOut(duration: 0.3)) {
                verticalOffset = CGFloat(sin(Date().timeIntervalSince1970 * 10) * 5)
            }
        }
    }

    private func statusItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(RBFont.caption(10)).foregroundStyle(RBColor.textTertiary)
            Text(value).font(RBFont.metric(18)).foregroundStyle(color)
        }
    }
}

/// 레이저 광선 및 지면 타겟 시각화
struct LaserBeamView: View {
    let pitch: Double
    let servoAngle: Double
    
    var body: some View {
        GeometryReader { geo in
            let beamColor = RBColor.accent
            
            // 빔의 끝점(지면) 계산 (단순 시각화용 모델)
            // 몸이 앞으로 기울면(Pitch+) 빔은 뒤로 가고, 서보가 보정하면 다시 앞으로 감
            let totalAngle = (90 - pitch) + (servoAngle - 85)
            let xOffset = tan(degreesToRadians(totalAngle - 90)) * 200
            
            ZStack {
                // 1. 광선 줄기
                Path { path in
                    path.move(to: CGPoint(x: geo.size.width/2, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width/2 + xOffset, y: 250))
                }
                .stroke(
                    LinearGradient(colors: [beamColor.opacity(0.8), beamColor.opacity(0)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 2
                )
                
                // 2. 지면 도트
                Circle()
                    .fill(beamColor)
                    .frame(width: 12, height: 8)
                    .blur(radius: 2)
                    .position(x: geo.size.width/2 + xOffset, y: 250)
                    .shadow(color: beamColor, radius: 10)
            }
        }
    }
    
    private func degreesToRadians(_ degrees: Double) -> Double {
        return degrees * .pi / 180
    }
}

#Preview {
    RunnerSimulationView()
        .environmentObject(MockBLEService())
}
