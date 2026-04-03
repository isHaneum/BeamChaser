import SwiftUI

/// 일시정지 / 종료 화면 (Tab 3)
/// - 네온 그린 재개 + 네온 레드 종료 버튼
/// - 운동 요약 그리드 (거리 | 시간 | 페이스 | 칼로리)
struct PauseFinishView: View {
    @EnvironmentObject var session: WatchSessionManager
    @State private var showFinishConfirm = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showFinishConfirm {
                finishConfirmView
            } else {
                mainButtonsView
            }
        }
    }

    // MARK: - 메인 버튼 화면

    private var mainButtonsView: some View {
        VStack(spacing: 0) {
            // 상단 헤더
            HStack {
                Text(Date(), style: .time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(session.isPaused ? "일시정지됨" : "러닝 중")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Spacer(minLength: 6)

            // 재개 / 일시정지 버튼 (네온 그린 / 오렌지)
            Button {
                if session.isPaused { session.resumeRun() } else { session.pauseRun() }
                HapticEngine.shared.trigger(.milestone)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(session.isPaused ? "재개" : "일시정지")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    session.isPaused
                    ? Color(red: 0.2, green: 0.85, blue: 0.4)
                    : Color(red: 1.0, green: 0.55, blue: 0.0)
                )
                .cornerRadius(10)
                .shadow(
                    color: (session.isPaused
                            ? Color(red: 0.2, green: 0.85, blue: 0.4)
                            : Color(red: 1.0, green: 0.55, blue: 0.0)).opacity(0.4),
                    radius: 8
                )
            }
            .buttonStyle(.plain)
            .foregroundColor(.black)
            .padding(.horizontal, 10)

            Spacer(minLength: 6)

            // 종료 버튼 (네온 레드)
            Button { showFinishConfirm = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("러닝 종료")
                        .font(.system(size: 13, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(neonRed.opacity(0.9))
                .cornerRadius(9)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .padding(.horizontal, 10)

            Spacer(minLength: 6)

            // 운동 요약 2x2 그리드
            summaryGrid
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
    }

    // MARK: - 요약 그리드

    private var summaryGrid: some View {
        let items: [(String, String)] = [
            ("거리", String(format: "%.2f km", session.snapshot.distanceMeters / 1000)),
            ("시간", elapsedText),
            ("페이스", PaceFormatter.format(session.snapshot.currentPaceSecondsPerKm)),
            ("칼로리", "--")
        ]
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 4
        ) {
            ForEach(items, id: \.0) { label, value in
                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .cornerRadius(5)
            }
        }
    }

    // MARK: - 종료 확인

    private var finishConfirmView: some View {
        VStack(spacing: 14) {
            Text("러닝을 종료할까요?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button { showFinishConfirm = false } label: {
                    Text("취소")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.gray.opacity(0.25))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)

                Button {
                    session.finishRun()
                    HapticEngine.shared.trigger(.milestone)
                    showFinishConfirm = false
                } label: {
                    Text("종료")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(neonRed)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Helpers

    private let neonRed = Color(red: 1.0, green: 0.12, blue: 0.12)

    private var elapsedText: String {
        let secs = Int(session.snapshot.elapsedSeconds)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
