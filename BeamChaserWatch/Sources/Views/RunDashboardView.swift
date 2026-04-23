import SwiftUI

/// 메인 러닝 대시보드 (Tab 1)
/// - 상단: 시간 | 심박수(네온 레드) | GPS 도트
/// - 중앙: 원형 레이저 게이지  — 네온 레드/그린 글로우 아크 + 거대 Gap 숫자
/// - 하단: 2x2 데이터 그리드 (페이스 | 시간 | 거리 | 속도)
struct RunDashboardView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)
                chaserGauge
                Spacer(minLength: 4)
                dataGrid
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

    // 상단: 시간 | 심박수 | GPS
    private var topBar: some View {
        HStack(spacing: 4) {
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
                .padding(.trailing, 5)
            }
            GPSSignalDots(accuracy: session.snapshot.gpsAccuracy)
        }
        .frame(height: 16)
    }

    // 중앙: 원형 레이저 게이지
    private var chaserGauge: some View {
        ZStack {
            // 배경 링
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 12)
                .frame(width: 106, height: 106)

            // 격차 아크 (글로우)
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(gapColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 106, height: 106)
                .shadow(color: gapColor.opacity(0.65), radius: 8)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: arcFraction)

            // 중앙 텍스트
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 1) {
                    Text(gapText)
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    Text("m")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 7)
                }
                Text(gapLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(gapColor)
                    .tracking(0.4)
            }
        }
    }

    // 하단: 2x2 데이터 그리드
    private var dataGrid: some View {
        let items: [(String, String)] = [
            ("페이스", PaceFormatter.format(session.snapshot.currentPaceSecondsPerKm)),
            ("시간",   elapsedText),
            ("거리",   String(format: "%.2f km", session.snapshot.distanceMeters / 1000)),
            ("케이던스", cadenceText)
        ]
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 4
        ) {
            ForEach(items, id: \.0) { label, value in
                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(neonRed)
                        .monospacedDigit()
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

    // MARK: - Helpers

    private let neonRed = Color(red: 1.0, green: 0.12, blue: 0.12)
    private var gapInt: Int { Int(session.snapshot.gapMeters.rounded()) }

    private var gapText: String { gapInt >= 0 ? "+\(gapInt)" : "\(gapInt)" }

    private var gapLabel: String {
        if gapInt > 0 { return "앞서는 중" }
        if gapInt < 0 { return "뒤처지는 중" }
        return "ON PACE"
    }

    private var gapColor: Color {
        if gapInt > 0 { return Color(red: 0.2, green: 0.85, blue: 0.4) }
        if gapInt < 0 { return neonRed }
        return Color(red: 1.0, green: 0.55, blue: 0.0)
    }

    private var arcFraction: Double {
        let absGap = min(abs(Double(gapInt)), 50.0)
        return absGap / 50.0 * 0.75
    }

    private var elapsedText: String {
        let secs = Int(session.snapshot.elapsedSeconds)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private var speedText: String {
        let pace = session.snapshot.currentPaceSecondsPerKm
        guard pace > 0, pace.isFinite, pace < 3600 else { return "--" }
        return String(format: "%.1f km/h", 3600.0 / pace)
    }

    private var cadenceText: String {
        let cadence = session.snapshot.currentCadenceSpm
        guard cadence > 0 else { return "--" }
        return "\(cadence) spm"
    }
}

// MARK: - GPS 신호 도트 (4개 원 — accuracy 낮을수록 good)
// Internal 접근성: QuickStartView 등 같은 모듈에서 공유
struct GPSSignalDots: View {
    let accuracy: Double   // CLLocation.horizontalAccuracy (m), -1 = 미수신

    private var filledCount: Int {
        guard accuracy >= 0 else { return 0 }
        switch accuracy {
        case ..<5:   return 4
        case ..<15:  return 3
        case ..<50:  return 2
        case ..<100: return 1
        default:     return 0
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
