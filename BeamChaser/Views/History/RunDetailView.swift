import SwiftUI
import MapKit

struct RunDetailView: View {
    let record: RunRecord
    @EnvironmentObject var runSession: RunSessionManager
    @State private var showShareCard = false

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // 지도에 경로 표시
                    if record.routePoints.count >= 2 {
                        Map {
                            MapPolyline(coordinates: record.routePoints.map(\.coordinate))
                                .stroke(
                                    LinearGradient(
                                        colors: [RBColor.accent, RBColor.accent.opacity(0.7)],
                                        startPoint: .leading, endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                                )

                            if let first = record.routePoints.first {
                                Annotation("", coordinate: first.coordinate) {
                                    Circle()
                                        .fill(RBColor.success)
                                        .frame(width: 10, height: 10)
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                }
                            }

                            if let last = record.routePoints.last {
                                Annotation("", coordinate: last.coordinate) {
                                    Circle()
                                        .fill(RBColor.danger)
                                        .frame(width: 10, height: 10)
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                }
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // 날짜
                    Text(record.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(RBFont.caption(13))
                        .foregroundStyle(RBColor.textSecondary)

                    // 메인 수치
                    HStack(spacing: 0) {
                        MetricView(label: "거리", value: String(format: "%.2f", record.totalDistanceMeters / 1000.0), unit: "km")
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(RBColor.divider).frame(width: 1, height: 40)
                        MetricView(label: "시간", value: record.formattedDuration, unit: "")
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(RBColor.divider).frame(width: 1, height: 40)
                        MetricView(label: "평균 페이스", value: record.formattedPace, unit: "")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                    .background(RBColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)

                    // 추가 상세 수치
                    detailStats
                        .padding(.horizontal, 16)

                    // 목표 페이스 결과
                    if let target = record.targetPace {
                        let diff = record.averagePaceSecondsPerKm - target.totalSecondsPerKm
                        let achieved = diff <= 0

                        HStack(spacing: 12) {
                            LaserDot(size: 12, glowRadius: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("목표 페이스")
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.textSecondary)
                                Text(target.formatted)
                                    .font(RBFont.metric(18))
                                    .foregroundStyle(RBColor.textPrimary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(achieved ? "달성" : "미달성")
                                    .font(RBFont.label(14))
                                    .foregroundStyle(achieved ? RBColor.success : RBColor.danger)
                                Text(String(format: "%@%d초", diff <= 0 ? "" : "+", Int(diff)))
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background((achieved ? RBColor.success : RBColor.danger).opacity(0.15))
                            .clipShape(Capsule())
                        }
                        .padding(16)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // 구간별 페이스 (킬로미터 스플릿)
                    if !kmSplits.isEmpty {
                        splitSection
                            .padding(.horizontal, 16)
                    }

                    // 이전 기록 대비 비교
                    comparisonSection
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("러닝 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RBColor.accent)
                }
            }
        }
        .sheet(isPresented: $showShareCard) {
            RunShareCardView(record: record)
        }
    }

    // MARK: - 추가 상세 수치

    private var detailStats: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statItem(label: "평균 속도", value: String(format: "%.1f km/h", avgSpeedKmh))
                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)
                statItem(label: "최고 속도", value: String(format: "%.1f km/h", maxSpeedKmh))
            }

            Divider().overlay(RBColor.divider)

            HStack(spacing: 0) {
                statItem(label: "총 고도 상승", value: String(format: "%.0f m", elevationGain))
                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)
                statItem(label: "칼로리 (추정)", value: String(format: "%.0f kcal", estimatedCalories))
            }
        }
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(RBFont.metric(16))
                .foregroundStyle(RBColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - 구간별 페이스 (스플릿)

    private var kmSplits: [(km: Int, pace: Double)] {
        guard record.routePoints.count >= 2 else { return [] }

        var splits: [(km: Int, pace: Double)] = []
        var accumulated: Double = 0
        var kmStart: Int = 0
        var segmentStartTime: Date? = record.routePoints.first?.timestamp

        for i in 1..<record.routePoints.count {
            let prev = CLLocation(latitude: record.routePoints[i-1].latitude, longitude: record.routePoints[i-1].longitude)
            let curr = CLLocation(latitude: record.routePoints[i].latitude, longitude: record.routePoints[i].longitude)
            accumulated += curr.distance(from: prev)

            let currentKm = Int(accumulated / 1000.0)
            if currentKm > kmStart {
                if let startTime = segmentStartTime {
                    let elapsed = record.routePoints[i].timestamp.timeIntervalSince(startTime)
                    splits.append((km: kmStart + 1, pace: elapsed))
                }
                kmStart = currentKm
                segmentStartTime = record.routePoints[i].timestamp
            }
        }

        return splits
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("구간별 페이스".uppercased())
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            let bestPace = kmSplits.map(\.pace).min() ?? 0

            ForEach(kmSplits, id: \.km) { split in
                HStack(spacing: 12) {
                    Text("\(split.km) km")
                        .font(RBFont.label(13))
                        .foregroundStyle(RBColor.textSecondary)
                        .frame(width: 44, alignment: .leading)

                    // 바
                    GeometryReader { geo in
                        let maxWidth = geo.size.width
                        let ratio = bestPace > 0 ? min(1.0, bestPace / split.pace) : 0.5
                        RoundedRectangle(cornerRadius: 3)
                            .fill(split.pace == bestPace ? RBColor.success : RBColor.accent.opacity(0.6))
                            .frame(width: maxWidth * ratio, height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 20)

                    Text(RunRecord.formatPace(split.pace))
                        .font(RBFont.metric(14))
                        .foregroundStyle(split.pace == bestPace ? RBColor.success : .white)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 이전 기록 대비

    private var comparisonSection: some View {
        let previousRuns = runSession.savedRecords.filter { $0.id != record.id && $0.totalDistanceMeters > 100 }
        guard !previousRuns.isEmpty else { return AnyView(EmptyView()) }

        let avgPreviousPace = previousRuns.map(\.averagePaceSecondsPerKm).reduce(0, +) / Double(previousRuns.count)
        let diff = record.averagePaceSecondsPerKm - avgPreviousPace
        let improved = diff < 0

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("기록 분석".uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)

                HStack(spacing: 12) {
                    Image(systemName: improved ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(improved ? RBColor.success : RBColor.danger)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(improved ? "페이스 향상!" : "페이스 하락")
                            .font(RBFont.label(15))
                            .foregroundStyle(RBColor.textPrimary)
                        Text("평균 대비 \(String(format: "%.0f초", abs(diff)))/km \(improved ? "빠름" : "느림")")
                            .font(RBFont.caption(12))
                            .foregroundStyle(RBColor.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("평균")
                            .font(RBFont.caption(9))
                            .foregroundStyle(RBColor.textTertiary)
                        Text(RunRecord.formatPace(avgPreviousPace))
                            .font(RBFont.metric(14))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                }
            }
            .padding(16)
            .background(RBColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
    }

    // MARK: - Computed

    private var avgSpeedKmh: Double {
        guard record.elapsedSeconds > 0 else { return 0 }
        return (record.totalDistanceMeters / 1000.0) / (record.elapsedSeconds / 3600.0)
    }

    private var maxSpeedKmh: Double {
        let maxSpeed = record.routePoints.map(\.speed).max() ?? 0
        return maxSpeed * 3.6
    }

    private var elevationGain: Double {
        guard record.routePoints.count >= 2 else { return 0 }
        var gain: Double = 0
        for i in 1..<record.routePoints.count {
            let diff = record.routePoints[i].altitude - record.routePoints[i-1].altitude
            if diff > 0 { gain += diff }
        }
        return gain
    }

    private var estimatedCalories: Double {
        // MET 기반 간단 추정: 러닝 MET ~10, 체중 70kg 가정
        let hours = record.elapsedSeconds / 3600.0
        return 10.0 * 70.0 * hours
    }
}

#Preview {
    NavigationStack {
        RunDetailView(record: RunRecord(
            id: UUID(),
            startDate: Date(),
            routePoints: [],
            totalDistanceMeters: 5230,
            elapsedSeconds: 1800,
            targetPace: PaceTarget(minutesPerKm: 5, secondsPerKm: 30)
        ))
        .environmentObject(RunSessionManager())
    }
}
