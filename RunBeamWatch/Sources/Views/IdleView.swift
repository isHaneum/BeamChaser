import SwiftUI

/// 러닝 비활성 상태에서 보이는 대기 화면
struct IdleView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 30))
                    .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.0))

                Text("RunBeam")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text("iPhone에서 러닝을\n시작하세요")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                // 연결 상태
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isPhoneReachable
                              ? Color(red: 0.2, green: 0.85, blue: 0.4)
                              : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(session.isPhoneReachable ? "iPhone 연결됨" : "연결 대기 중")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
            }
        }
    }
}
