import SwiftUI

struct RunHistoryView: View {
    @EnvironmentObject var runSession: RunSessionManager

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                if runSession.savedRecords.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // 통계 요약 카드
                            summaryCard
                                .padding(.horizontal, 16)

                            // 페이스 추이 (최근 기록)
                            if runSession.savedRecords.count >= 2 {
                                paceTrendCard
                                    .padding(.horizontal, 16)
                            }

                            // 기록 리스트
                            LazyVStack(spacing: 12) {
                                ForEach(runSession.savedRecords) { record in
                                    NavigationLink(destination: RunDetailView(record: record)) {
                                        runRecordCard(record)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("러닝 기록")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - 통계 요약

    private var summaryCard: some View {
        let records = runSession.savedRecords.filter { $0.totalDistanceMeters > 100 }
        let totalDistance = records.map(\.totalDistanceMeters).reduce(0, +)
        let totalTime = records.map(\.elapsedSeconds).reduce(0, +)
        let avgPace = records.isEmpty ? 0 : records.map(\.averagePaceSecondsPerKm).reduce(0, +) / Double(records.count)
        let bestPace = records.map(\.averagePaceSecondsPerKm).filter { $0 > 0 }.min() ?? 0

        return VStack(spacing: 12) {
            HStack {
                Text("전체 통계".uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)
                Spacer()
                Text("\(records.count)회 러닝")
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.accent)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("총 거리")
                        .font(RBFont.caption(9))
                        .foregroundStyle(RBColor.textTertiary)
                    Text(String(format: "%.1f", totalDistance / 1000.0))
                        .font(RBFont.metric(22))
                        .foregroundStyle(RBColor.textPrimary)
                    Text("km")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textSecondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)

                VStack(spacing: 2) {
                    Text("총 시간")
                        .font(RBFont.caption(9))
                        .foregroundStyle(RBColor.textTertiary)
                    Text(RunRecord.formatDuration(totalTime))
                        .font(RBFont.metric(22))
                        .foregroundStyle(RBColor.textPrimary)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)

                VStack(spacing: 2) {
                    Text("평균 페이스")
                        .font(RBFont.caption(9))
                        .foregroundStyle(RBColor.textTertiary)
                    Text(RunRecord.formatPace(avgPace))
                        .font(RBFont.metric(22))
                        .foregroundStyle(RBColor.textPrimary)
                    Text("/km")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textSecondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)

                VStack(spacing: 2) {
                    Text("최고 페이스")
                        .font(RBFont.caption(9))
                        .foregroundStyle(RBColor.textTertiary)
                    Text(RunRecord.formatPace(bestPace))
                        .font(RBFont.metric(22))
                        .foregroundStyle(RBColor.success)
                    Text("/km")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 페이스 추이

    private var paceTrendCard: some View {
        let recentRuns = Array(runSession.savedRecords.filter { $0.totalDistanceMeters > 100 }.prefix(10)).reversed()
        let paces = Array(recentRuns).map(\.averagePaceSecondsPerKm)
        guard let minPace = paces.filter({ $0 > 0 }).min(),
              let maxPace = paces.max(), maxPace > minPace else {
            return AnyView(EmptyView())
        }

        let range = maxPace - minPace
        let isImproving = paces.count >= 2 && paces.last! < paces.first!

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("페이스 추이".uppercased())
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(1)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: isImproving ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(isImproving ? "향상 중" : "하락 중")
                            .font(RBFont.caption(11))
                    }
                    .foregroundStyle(isImproving ? RBColor.success : RBColor.danger)
                }

                // 미니 그래프
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let stepX = paces.count > 1 ? w / CGFloat(paces.count - 1) : 0

                    Path { path in
                        for (i, pace) in paces.enumerated() {
                            let x = CGFloat(i) * stepX
                            let normalizedY = (pace - minPace) / range
                            let y = h * (1.0 - normalizedY) * 0.8 + h * 0.1  // 페이스 낮을수록(빠를수록) 위
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [RBColor.accent, isImproving ? RBColor.success : RBColor.danger],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // 데이터 포인트
                    ForEach(0..<paces.count, id: \.self) { i in
                        let x = CGFloat(i) * stepX
                        let normalizedY = (paces[i] - minPace) / range
                        let y = h * (1.0 - normalizedY) * 0.8 + h * 0.1
                        Circle()
                            .fill(i == paces.count - 1 ? RBColor.accent : Color.white.opacity(0.5))
                            .frame(width: i == paces.count - 1 ? 6 : 4, height: i == paces.count - 1 ? 6 : 4)
                            .position(x: x, y: y)
                    }
                }
                .frame(height: 60)
                .padding(.horizontal, 4)

                // 최근 vs 처음 비교
                HStack {
                    Text("처음: \(RunRecord.formatPace(paces.first ?? 0))")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                    Spacer()
                    Text("최근: \(RunRecord.formatPace(paces.last ?? 0))")
                        .font(RBFont.caption(10))
                        .foregroundStyle(isImproving ? RBColor.success : RBColor.danger)
                }
            }
            .padding(16)
            .background(RBColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56))
                .foregroundStyle(RBColor.textTertiary)
            Text("러닝 기록이 없습니다")
                .font(RBFont.label(17))
                .foregroundStyle(RBColor.textSecondary)
            Text("첫 러닝을 시작해보세요!")
                .font(RBFont.caption(14))
                .foregroundStyle(RBColor.textTertiary)
        }
    }

    private func runRecordCard(_ record: RunRecord) -> some View {
        HStack(spacing: 14) {
            // 날짜 뱃지
            VStack(spacing: 2) {
                Text(record.startDate.formatted(.dateTime.month(.abbreviated)))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .textCase(.uppercase)
                Text(record.startDate.formatted(.dateTime.day()))
                    .font(RBFont.metric(22))
                    .foregroundStyle(RBColor.textPrimary)
            }
            .frame(width: 48)

            // 구분선
            Rectangle()
                .fill(RBColor.divider)
                .frame(width: 1, height: 40)

            // 데이터
            VStack(alignment: .leading, spacing: 6) {
                Text(record.formattedDistance)
                    .font(RBFont.metric(20))
                    .foregroundStyle(RBColor.textPrimary)
                HStack(spacing: 14) {
                    Label(record.formattedPace, systemImage: "speedometer")
                    Label(record.formattedDuration, systemImage: "clock")
                }
                .font(RBFont.caption(12))
                .foregroundStyle(RBColor.textSecondary)
            }

            Spacer()

            if record.targetPace != nil {
                LaserDot(size: 10, glowRadius: 6)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RBColor.textTertiary)
        }
        .padding(14)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    RunHistoryView()
        .environmentObject(RunSessionManager())
}
