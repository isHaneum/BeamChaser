import SwiftUI

/// 앱 실행 즉시 화면: 거대한 네온 레드 원형 버튼으로 즉시 러닝 시작
/// - 디지털 크라운: 목표 페이스 조절
struct QuickStartView: View {
    @EnvironmentObject var session: WatchSessionManager

    @State private var targetPaceSeconds: Double = 360  // 기본 6:00/km
    private let minPace: Double = 180   // 3:00/km
    private let maxPace: Double = 720   // 12:00/km

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                quickRunButton
                Spacer()
                paceControl
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .focusable()
        .digitalCrownRotation(
            $targetPaceSeconds,
            from: minPace,
            through: maxPace,
            by: 5.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            let t = session.snapshot.targetPaceSecondsPerKm
            if t > 0 { targetPaceSeconds = min(maxPace, max(minPace, t)) }
        }
    }

    // 상단: 시간 | 심박수 | GPS
    private var topBar: some View {
        HStack(spacing: 0) {
            Text(Date(), style: .time)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            if session.snapshot.heartRate > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                    Text("\(session.snapshot.heartRate)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(neonRed)
                .padding(.trailing, 6)
            }
            GPSSignalDots(accuracy: session.snapshot.gpsAccuracy)
        }
        .frame(height: 16)
    }

    // 거대한 네온 레드 원형 버튼
    private var quickRunButton: some View {
        Button {
            session.startRun(targetPace: targetPaceSeconds)
            HapticEngine.shared.trigger(.milestone)
        } label: {
            ZStack {
                // 글로우 링
                Circle()
                    .stroke(neonRed.opacity(0.22), lineWidth: 6)
                    .frame(width: 116, height: 116)
                    .shadow(color: neonRed.opacity(0.5), radius: 14)

                // 메인 원
                Circle()
                    .fill(neonRed.opacity(0.09))
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(neonRed, lineWidth: 1.5))

                // 아이콘 + 텍스트
                VStack(spacing: 5) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(neonRed)
                    Text("QUICK RUN")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .tracking(1.8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // 목표 페이스 표시 + 크라운 안내
    private var paceControl: some View {
        VStack(spacing: 3) {
            Text(PaceFormatter.format(targetPaceSeconds))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(neonRed)
                .monospacedDigit()
            Text("크라운으로 목표 페이스 조절")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }

    private let neonRed = Color(red: 1.0, green: 0.12, blue: 0.12)
}
