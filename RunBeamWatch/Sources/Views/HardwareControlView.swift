import SwiftUI

/// 하드웨어 제어 화면 (Tab 2)
/// - 디지털 크라운: 레이저 밀기 조절 (0단 100%)
/// - ▼▲ 버튼: 서보 영점 미세조절 (±5도)
struct HardwareControlView: View {
    @EnvironmentObject var session: WatchSessionManager

    // 밤기: 로컈 상태 (BLE 피드백 없음, UI 전용)
    @State private var brightness: Double = 100
    // 서보 오프셋 (-25 ~ +25)
    @State private var servoOffset: Int = 0
    @State private var lastSentAngle: Int = 85

    private let minBrightness: Double = 10
    private let maxBrightness: Double = 100

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                Spacer(minLength: 0)
                brightnessSection
                Spacer(minLength: 0)
                servoSection
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
        .focusable()
        .digitalCrownRotation(
            $brightness,
            from: minBrightness,
            through: maxBrightness,
            by: 5.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            servoOffset = max(-25, min(25, session.snapshot.servoAngle - 85))
            lastSentAngle = session.snapshot.servoAngle
        }
        .onChange(of: session.snapshot.servoAngle) { _, newAngle in
            let offset = newAngle - 85
            if abs(offset - servoOffset) > 1 {
                servoOffset = max(-25, min(25, offset))
                lastSentAngle = newAngle
            }
        }
    }

    // MARK: - 상단: 시간 | 심박 | '\uae30기 제어' | 배터리
    private var topBar: some View {
        HStack(spacing: 0) {
            Text(Date(), style: .time)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            if session.snapshot.heartRate > 0 {
                Image(systemName: "heart.fill")
                    .font(.system(size: 8))
                    .foregroundColor(neonRed)
                    .padding(.trailing, 4)
            }
            Text("\(session.snapshot.deviceBattery)%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(batteryColor)
        }
        .frame(height: 14)
    }

    // MARK: - 수평 밀기 슬라이더
    private var brightnessSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("레이저 밀기")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundColor(.gray.opacity(0.6))
                    Text("\(Int(brightness))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(neonRed)
                        .monospacedDigit()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 배경
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 18)

                    // 채워진 영역 (네온 레드 레이저 블)
                    let ratio = CGFloat((brightness - minBrightness) / (maxBrightness - minBrightness))
                    let fillWidth = max(18, geo.size.width * ratio)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [neonRed.opacity(0.5), neonRed],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: 18)
                        .shadow(color: neonRed.opacity(0.6), radius: 6)
                        .animation(.easeOut(duration: 0.1), value: brightness)

                    // 노브 (crown 위치 표시)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: max(2, fillWidth - 10))
                        .animation(.easeOut(duration: 0.1), value: brightness)
                }
            }
            .frame(height: 18)
        }
    }

    // MARK: - 서보 영점 조절
    private var servoSection: some View {
        VStack(spacing: 6) {
            Text("레이저 투사 영점 조절")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
                .tracking(0.5)

            HStack(spacing: 10) {
                // 아래(-5도)
                Button { stepServo(by: -5) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 36)
                        .background(neonRed.opacity(0.14))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(neonRed.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundColor(neonRed)

                // 각도 표시
                VStack(spacing: 0) {
                    Text(servoOffset >= 0 ? "+\(servoOffset)" : "\(servoOffset)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text("도")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                .frame(width: 44)

                // 위(+5도)
                Button { stepServo(by: 5) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 36)
                        .background(neonRed.opacity(0.14))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(neonRed.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundColor(neonRed)
            }
        }
    }

    // MARK: - Helpers

    private func stepServo(by delta: Int) {
        let newOffset = max(-25, min(25, servoOffset + delta))
        let actualDelta = newOffset - servoOffset
        guard actualDelta != 0 else { return }
        servoOffset = newOffset
        session.adjustServo(actualDelta)
        lastSentAngle = 85 + newOffset
    }

    private let neonRed = Color(red: 1.0, green: 0.12, blue: 0.12)

    private var batteryColor: Color {
        let b = session.snapshot.deviceBattery
        if b > 50 { return Color(red: 0.2, green: 0.85, blue: 0.4) }
        if b > 20 { return Color(red: 1.0, green: 0.55, blue: 0.0) }
        return neonRed
    }
}
