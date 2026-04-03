import SwiftUI

/// 메인 러닝 대시보드 (Tab 1)
/// - 상단: GPS 신호 도트
/// - 중앙: 거대 Gap 게이지  (+Xm 초록 / -Xm 빨강)
/// - 하단: 심박수 | 페이스 | 경과시간
struct RunDashboardView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 상단: GPS + 연결 상태 ──────────────────────────
                topBar

                Spacer()

                // ── 중앙: Gap 게이지 ──────────────────────────────
                gapHero

                Spacer()

                // ── 하단: 심박수 | 페이스 | 시간 ──────────────────
                bottomBar
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .onChange(of: session.snapshot.paceStatus) { _, newStatus in
            switch newStatus {
            case "behind":    HapticEngine.shared.trigger(.behind)
            case "ahead":     HapticEngine.shared.trigger(.ahead)
            default: break
            }
        }
    }

    // MARK: - Sub Views

    private var topBar: some View {
        HStack(spacing: 6) {
            // GPS 신호 도트 (최대 4칸)
            GPSSignalDots(strength: session.snapshot.gpsAccuracy)

            Spacer()

            // iPhone 연결 상태
            Circle()
                .fill(session.isPhoneReachable ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)

            // 심박수
            if session.snapshot.heartRate > 0 {
                Text("\(session.snapshot.heartRate)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                + Text(" bpm")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
        .frame(height: 18)
    }

    private var gapHero: some View {
        VStack(spacing: 2) {
            // 레이블
            Text(gapLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
                .textCase(.uppercase)
                .tracking(1.2)

            // 메인 숫자
            Text(gapText)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundColor(gapColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .monospacedDigit()

            // 단위
            Text("m")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(gapColor.opacity(0.7))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // 페이스
            VStack(spacing: 1) {
                Text(PaceFormatter.format(session.snapshot.currentPaceSecondsPerKm))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Text("페이스")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)

            // 구분선
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 24)

            // 경과 시간
            VStack(spacing: 1) {
                Text(elapsedText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Text("시간")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 36)
    }

    // MARK: - Helpers

    private var gapInt: Int { Int(session.snapshot.gapMeters.rounded()) }

    private var gapText: String {
        gapInt >= 0 ? "+\(gapInt)" : "\(gapInt)"
    }

    private var gapLabel: String {
        if gapInt > 0  { return "앞서는 거리" }
        if gapInt < 0  { return "뒤처진 거리" }
        return "페이스 일치"
    }

    private var gapColor: Color {
        if gapInt > 0  { return Color(red: 0.2, green: 0.85, blue: 0.4) }
        if gapInt < 0  { return Color(red: 1.0, green: 0.2, blue: 0.2) }
        return Color(red: 1.0, green: 0.55, blue: 0.0)
    }

    private var elapsedText: String {
        let secs = Int(session.snapshot.elapsedSeconds)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - GPS Signal Dots

private struct GPSSignalDots: View {
    let strength: Double  // 0~1 (1 = 최상)

    private var filledCount: Int {
        switch strength {
        case 0.8...: return 4
        case 0.5...: return 3
        case 0.2...: return 2
        case 0.01...: return 1
        default: return 0
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < filledCount
                          ? Color(red: 0.2, green: 0.85, blue: 0.4)
                          : Color.gray.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

#Preview {
    RunDashboardView()
        .environmentObject({
            let m = WatchSessionManager()
            return m
        }())
}
