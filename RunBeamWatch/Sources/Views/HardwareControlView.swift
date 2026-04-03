import SwiftUI

/// 하드웨어 제어 화면 (Tab 2)
/// - Digital Crown: 서보 각도 조절 (-30 ~ +30 도)
/// - 위/아래 버튼: 서보 ±5도 수동 조절
/// - 하단: 장치 배터리 표시
struct HardwareControlView: View {
    @EnvironmentObject var session: WatchSessionManager

    // Digital Crown 누적 값 (-25 ~ +25, 0 = 중앙 85도)
    @State private var crownValue: Double = 0
    @State private var lastSentAngle: Int = 85

    private let minAngle: Double = -25
    private let maxAngle: Double =  25

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                // ── 상단 제목 ───────────────────────────────────
                Text("레이저 각도")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                    .tracking(0.8)

                // ── 각도 표시 ──────────────────────────────────
                angleDisplay

                // ── 위아래 버튼 ────────────────────────────────
                controlButtons

                Spacer()

                // ── 배터리 ─────────────────────────────────────
                batteryRow
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: minAngle,
            through: maxAngle,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newVal in
            let angle = Int(newVal.rounded())
            if angle != lastSentAngle {
                let delta = angle - lastSentAngle
                session.adjustServo(delta)
                lastSentAngle = angle
            }
        }
        .onAppear {
            let offset = session.snapshot.servoAngle - 85
            crownValue = Double(max(-25, min(25, offset)))
            lastSentAngle = session.snapshot.servoAngle
        }
        .onChange(of: session.snapshot.servoAngle) { _, newAngle in
            // iPhone이 서보 각도를 확정하면 Crown 값 동기화
            let offset = Double(newAngle - 85)
            if abs(offset - crownValue) > 1 {
                crownValue = max(minAngle, min(maxAngle, offset))
                lastSentAngle = newAngle
            }
        }
    }

    // MARK: - Sub Views

    private var angleDisplay: some View {
        ZStack {
            // 배경 원호 (전체 범위 표시)
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: 72, height: 72)

            // 활성 원호 (현재 위치까지)
            let progress = (crownValue - minAngle) / (maxAngle - minAngle)
            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * progress)
                .stroke(
                    Color(red: 1.0, green: 0.55, blue: 0.0),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: 72, height: 72)
                .animation(.easeOut(duration: 0.1), value: crownValue)

            // 각도 텍스트
            VStack(spacing: 0) {
                Text("\(Int(crownValue.rounded()))")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("도")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 16) {
            // -5도 버튼
            Button {
                let newVal = max(minAngle, crownValue - 5)
                let delta = Int(newVal.rounded()) - Int(crownValue.rounded())
                crownValue = newVal
                if delta != 0 {
                    session.adjustServo(delta)
                    lastSentAngle = Int(newVal.rounded())
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 32)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // 리셋 버튼 (0도)
            Button {
                let delta = 0 - Int(crownValue.rounded())
                crownValue = 0
                if delta != 0 {
                    session.adjustServo(delta)
                    lastSentAngle = 0
                }
            } label: {
                Text("0")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.gray)

            // +5도 버튼
            Button {
                let newVal = min(maxAngle, crownValue + 5)
                let delta = Int(newVal.rounded()) - Int(crownValue.rounded())
                crownValue = newVal
                if delta != 0 {
                    session.adjustServo(delta)
                    lastSentAngle = Int(newVal.rounded())
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 32)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
    }

    private var batteryRow: some View {
        HStack(spacing: 6) {
            Image(systemName: batteryIcon)
                .font(.system(size: 12))
                .foregroundColor(batteryColor)
            Text("\(session.snapshot.deviceBattery)%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(batteryColor)
            Text("장치")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
    }

    // MARK: - Helpers

    private var batteryColor: Color {
        let b = session.snapshot.deviceBattery
        if b > 50 { return Color(red: 0.2, green: 0.85, blue: 0.4) }
        if b > 20 { return Color(red: 1.0, green: 0.55, blue: 0.0) }
        return Color(red: 1.0, green: 0.2, blue: 0.2)
    }

    private var batteryIcon: String {
        let b = session.snapshot.deviceBattery
        if b > 75 { return "battery.100" }
        if b > 50 { return "battery.75" }
        if b > 25 { return "battery.50" }
        if b > 10 { return "battery.25" }
        return "battery.0"
    }
}
