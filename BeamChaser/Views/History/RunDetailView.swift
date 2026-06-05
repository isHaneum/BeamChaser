import SwiftUI
import MapKit

struct RunDetailView: View {
    let record: RunRecord
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var runSession: RunSessionManager
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @State private var showShareCard = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isSensorDetailExpanded = false

    private let detailColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    routeMapSection

                    primaryStatsSection
                        .padding(.horizontal, 20)

                    sensorAccuracySection
                        .padding(.horizontal, 20)

                    // 목표 페이스 결과
                    if let target = record.targetPace {
                        let diff = record.averagePaceSecondsPerKm - target.totalSecondsPerKm
                        let achieved = diff <= 0

                        HStack(spacing: 12) {
                            LaserDot(size: 12, glowRadius: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appLanguage.localized("목표 페이스"))
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.textSecondary)
                                Text(target.formatted)
                                    .font(RBFont.metric(18))
                                    .foregroundStyle(RBColor.textPrimary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(achieved ? appLanguage.localized("달성") : appLanguage.localized("미달성"))
                                    .font(RBFont.label(14))
                            .foregroundStyle(achieved ? RBColor.success : RBColor.danger)
                                Text(String(format: "%@%d초", diff <= 0 ? "" : "+", Int(diff)))
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background((achieved ? RBColor.success : RBColor.danger).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))
                        }
                        .padding(16)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
                        .padding(.horizontal, 20)
                    }

                    // 구간별 페이스 (킬로미터 스플릿)
                    if !kmSplits.isEmpty {
                        splitSection
                            .padding(.horizontal, 20)
                    }

                    // 이전 기록 대비 비교
                    comparisonSection
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
            .clipped()
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showShareCard) {
            RunShareCardView(record: record)
        }
        .onAppear {
            fitMapToRoute()
        }
    }

    private var routeMapSection: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all) {
                if record.routePoints.count >= 2 {
                    MapPolyline(coordinates: record.routePoints.map(\.coordinate))
                        .stroke(
                            LinearGradient(
                                colors: [RBColor.accent, RBColor.laserRed],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }

                if let first = record.routePoints.first {
                    Annotation("", coordinate: first.coordinate) {
                        Circle()
                            .fill(RBColor.success)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }

                if let last = record.routePoints.last {
                    Annotation("", coordinate: last.coordinate) {
                        Circle()
                            .fill(RBColor.danger)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.park, .publicTransport, .stadium])))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .frame(height: 370)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.48), Color.black.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLanguage.localized("러닝 상세"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .tracking(1.2)
                    Text(RunPresentationFormatter.scheduleString(from: record.startDate))
                        .font(RBFont.caption(12))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(appLanguage.text("내 러닝 경로", "My Running Route"))
                        .font(RBFont.title(24))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.68), Color.black.opacity(0.18), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }

            HStack(spacing: 12) {
                mapHeaderButton(systemName: onDone == nil ? "chevron.left" : "xmark") {
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }

                Spacer()

                mapHeaderButton(systemName: "map") {
                    fitMapToRoute()
                }

                mapHeaderButton(systemName: "square.and.arrow.up") {
                    showShareCard = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    private func mapHeaderButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.black.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 상세 수치

    private var primaryStatsSection: some View {
        LazyVGrid(columns: detailColumns, spacing: 12) {
            ForEach(detailMetricCards) { metric in
                statItem(metric)
            }
        }
    }

    private func statItem(_ metric: RunDetailMetricCardModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(0.8)
            RBMetricLine(
                value: metric.value,
                unit: metric.unit,
                valueFont: RBFont.metric(metric.isPrimary ? 30 : 20),
                unitFont: RBFont.unit(metric.isPrimary ? 13 : 11),
                valueColor: metric.isMuted ? RBColor.textSecondary : RBColor.textPrimary,
                unitColor: metric.isMuted ? RBColor.textTertiary : RBColor.textSecondary,
                spacing: 3,
                alignment: .leading
            )

            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(RBFont.caption(11))
                    .foregroundStyle(metric.isMuted ? RBColor.textTertiary : RBColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(RBColor.divider.opacity(0.72), lineWidth: 1)
        )
    }

    private var sensorAccuracySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSensorDetailExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(sensorQualityColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appLanguage.localized("GPS 오차 및 센서 정보"))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textTertiary)
                            .tracking(1)

                        Text(sensorQualityTitle)
                            .font(RBFont.label(15))
                            .foregroundStyle(RBColor.textPrimary)
                    }

                    Spacer()

                    Image(systemName: isSensorDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isSensorDetailExpanded {
                Text(sensorQualityDescription)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: detailColumns, spacing: 10) {
                    sensorPill(
                        title: appLanguage.text("GPS 품질", "GPS Quality"),
                        value: RunDetailMetricBuilder.gpsQualityLabel(metricAnalysis.dataQuality.gpsQuality, appLanguage: appLanguage)
                    )
                    sensorPill(
                        title: appLanguage.localized("GPS 평균 오차"),
                        value: averageGPSAccuracyMeters.map { String(format: "±%.0f m", $0) } ?? appLanguage.localized("데이터 적음")
                    )
                    sensorPill(
                        title: appLanguage.text("심박 소스", "Heart Source"),
                        value: RunDetailMetricBuilder.sourceLabel(metricAnalysis.dataQuality.heartRateSource, appLanguage: appLanguage)
                    )
                    sensorPill(
                        title: appLanguage.text("케이던스 소스", "Cadence Source"),
                        value: RunDetailMetricBuilder.sourceLabel(metricAnalysis.dataQuality.cadenceSource, appLanguage: appLanguage)
                    )
                    sensorPill(
                        title: appLanguage.text("고도 상태", "Elevation"),
                        value: metricAnalysis.dataQuality.hasReliableElevation
                            ? RunDetailMetricBuilder.sourceLabel(metricAnalysis.dataQuality.elevationSource, appLanguage: appLanguage)
                            : appLanguage.text("정보 없음", "Unavailable")
                    )
                    sensorPill(
                        title: appLanguage.text("최고 속도", "Top Speed"),
                        value: metricAnalysis.dataQuality.hasReliableSpeed
                            ? appLanguage.text("필터 적용", "Filtered")
                            : appLanguage.text("숨김", "Hidden")
                    )
                    sensorPill(title: appLanguage.localized("경로 포인트"), value: appLanguage.text("\(record.routePoints.count)개", "\(record.routePoints.count) pts"))
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private func sensorPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(RBFont.metric(14))
                .foregroundStyle(RBColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))
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
            Text(appLanguage.localized("구간별 페이스").uppercased())
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
                        .foregroundStyle(split.pace == bestPace ? RBColor.success : RBColor.textPrimary)
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
                Text(appLanguage.localized("기록 분석").uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)

                HStack(spacing: 12) {
                    Image(systemName: improved ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(improved ? RBColor.success : RBColor.danger)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(improved ? appLanguage.localized("페이스 향상!") : appLanguage.localized("페이스 하락"))
                            .font(RBFont.label(15))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(appLanguage.text("평균 대비 \(String(format: "%.0f초", abs(diff)))/km \(improved ? "빠름" : "느림")", "\(String(format: "%.0fs", abs(diff)))/km \(improved ? "faster" : "slower") than average"))
                            .font(RBFont.caption(12))
                            .foregroundStyle(RBColor.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(appLanguage.localized("평균"))
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

    private var metricAnalysis: RunMetricAnalysis {
        record.analyzedMetrics
    }

    private var detailMetricCards: [RunDetailMetricCardModel] {
        RunDetailMetricBuilder.cards(for: record, appLanguage: appLanguage)
    }

    private func fitMapToRoute() {
        let coordinates = record.routePoints.map(\.coordinate)
        guard !coordinates.isEmpty else {
            cameraPosition = .automatic
            return
        }

        guard coordinates.count > 1 else {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinates[0],
                    latitudinalMeters: 400,
                    longitudinalMeters: 400
                )
            )
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLon = longitudes.min(),
            let maxLon = longitudes.max()
        else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let latitudeDelta = max((maxLat - minLat) * 1.6, 0.004)
        let longitudeDelta = max((maxLon - minLon) * 1.6, 0.004)

        cameraPosition = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
            )
        )
    }

    private var averageGPSAccuracyMeters: Double? {
        metricAnalysis.averageGPSAccuracyMeters
    }

    private var sensorQualityTitle: String {
        switch metricAnalysis.dataQuality.gpsQuality {
        case .good:
            return appLanguage.text("GPS 품질 양호", "GPS quality good")
        case .fair:
            return appLanguage.text("GPS 품질 보통", "GPS quality fair")
        case .poor:
            return appLanguage.text("GPS 정확도 낮음", "GPS accuracy low")
        }
    }

    private var sensorQualityDescription: String {
        let accuracyText = averageGPSAccuracyMeters.map { String(format: "±%.0f m", $0) }
            ?? appLanguage.text("데이터 적음", "Limited data")
        let heartSource = RunDetailMetricBuilder.sourceDetail(for: metricAnalysis.dataQuality.heartRateSource, appLanguage: appLanguage)
        let cadenceSource = RunDetailMetricBuilder.sourceDetail(for: metricAnalysis.dataQuality.cadenceSource, appLanguage: appLanguage)

        switch metricAnalysis.dataQuality.gpsQuality {
        case .good:
            return appLanguage.text(
                "거리와 평균 속도는 수평 정확도 20m 이하 GPS 샘플만 반영했습니다. 최고 속도는 3초 이상 유지된 속도만 인정하고, 고도 상승은 수직 정확도 15m 이하 GPS를 보정해 누적했습니다. 평균 GPS 오차는 \(accuracyText), 심박 소스는 \(heartSource), 케이던스 소스는 \(cadenceSource)입니다.",
                "Distance and average speed only use GPS samples with horizontal accuracy of 20 m or better. Top speed requires sustained 3-second speed, and elevation gain only uses GPS altitude with vertical accuracy of 15 m or better after correction. Average GPS error was \(accuracyText), heart rate source was \(heartSource), and cadence source was \(cadenceSource)."
            )
        case .fair:
            return appLanguage.text(
                "GPS 정확도가 완전히 안정적이지 않아 최고 속도와 고도는 보수적으로 필터링했습니다. 수평 정확도 20m 초과 샘플과 비정상 속도는 제외했고, 평균 GPS 오차는 \(accuracyText)입니다.",
                "GPS quality was only fair, so top speed and elevation were filtered conservatively. Samples with horizontal accuracy above 20 m and abnormal speed spikes were excluded, and average GPS error was \(accuracyText)."
            )
        case .poor:
            return appLanguage.text(
                "GPS 품질이 낮아 최고 속도와 총 고도 상승은 숨겼습니다. 거리와 페이스는 남은 유효 GPS 샘플만 사용했고, 평균 GPS 오차는 \(accuracyText)입니다.",
                "GPS quality was poor, so top speed and elevation gain were hidden. Distance and pace only use the remaining valid GPS samples, and average GPS error was \(accuracyText)."
            )
        }
    }

    private var sensorQualityColor: Color {
        switch metricAnalysis.dataQuality.gpsQuality {
        case .good:
            return RBColor.success
        case .fair:
            return Color.orange
        case .poor:
            return RBColor.danger
        }
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
