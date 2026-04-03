import SwiftUI

/// 일시정지 / 종료 화면 (Tab 3)
/// - 러닝 중: 일시정지 + 종료 버튼
/// - 일시정지 중: 재개 + 종료 버튼
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

    // MARK: - 메인 버튼

    private var mainButtonsView: some View {
        VStack(spacing: 12) {
            // 상태 텍스트
            Text(session.isPaused ? "일시정지됨" : "러닝 중")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
                .tracking(0.8)

            // 일시정지 / 재개 버튼
            Button {
                if session.isPaused {
                    session.resumeRun()
                    HapticEngine.shared.trigger(.milestone)
                } else {
                    session.pauseRun()
                    HapticEngine.shared.trigger(.ahead)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(session.isPaused ? "재개" : "일시정지")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    session.isPaused
                    ? Color(red: 0.2, green: 0.85, blue: 0.4).opacity(0.9)
                    : Color(red: 1.0, green: 0.55, blue: 0.0).opacity(0.9)
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .foregroundColor(.black)

            // 종료 버튼
            Button {
                showFinishConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("러닝 종료")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.85))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - 종료 확인

    private var finishConfirmView: some View {
        VStack(spacing: 14) {
            Text("러닝을 종료할까요?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                // 취소
                Button {
                    showFinishConfirm = false
                } label: {
                    Text("취소")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)

                // 종료 확정
                Button {
                    session.finishRun()
                    HapticEngine.shared.trigger(.milestone)
                    showFinishConfirm = false
                } label: {
                    Text("종료")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(red: 1.0, green: 0.2, blue: 0.2))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
    }
}
