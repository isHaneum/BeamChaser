import SwiftUI
import MapKit

struct RunDetailView: View {
    let record: RunRecord
    var onDone: (() -> Void)? = nil
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
                VStack(spacing: 20) {
                    routeMapSection
                    summarySection

                    detailStatsSection
                        .padding(.horizontal, 16)

                    sensorAccuracySection
                        .padding(.horizontal, 16)

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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
            .clipped()
        }
        .navigationTitle(appLanguage.localized("러닝 상세"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDone()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                }
            }

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
        .fullScreenCover(isPresented: $showShareCard) {
            RunShareCardView(record: record)
        }
        .onAppear {
            fitMapToRoute()
        }
    }

    private var routeMapSection: some View {
        ZStack(alignment: .topTrailing) {
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
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RunPresentationFormatter.scheduleString(from: record.startDate))
                        .font(RBFont.caption(12))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(appLanguage.text("내 러닝 경로", "My Running Route"))
                        .font(RBFont.label(18))
                        .foregroundStyle(.white)
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.64), Color.black.opacity(0.18)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }

            Button {
                fitMapToRoute()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 12, weight: .semibold))
                    Text(appLanguage.text("경로 맞춤", "Fit Route"))
                        .font(RBFont.label(12))
                }
                .foregroundStyle(RBColor.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appLanguage.text("러닝 기록", "Run Summary"))
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1.2)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", record.distanceKm))
                    .font(RBFont.hero(50))
                    .foregroundStyle(RBColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("km")
                    .font(RBFont.label(18))
                    .foregroundStyle(RBColor.textSecondary)

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                summaryMetricCard(title: appLanguage.localized("시간"), value: record.formattedDuration)
                summaryMetricCard(title: appLanguage.localized("평균 페이스"), value: record.formattedPace)
            }
        }
        .padding(18)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func summaryMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
            Text(value)
                .font(RBFont.metric(22))
                .foregroundStyle(RBColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 추가 상세 수치

    private var detailStatsSection: some View {
        LazyVGrid(columns: detailColumns, spacing: 12) {
            statItem(label: appLanguage.localized("평균 심박수"), value: record.formattedAverageHeartRate)
            statItem(label: appLanguage.localized("칼로리 (추정)"), value: String(format: "%.0f kcal", estimatedCalories))
            statItem(label: appLanguage.localized("평균 속도"), value: String(format: "%.1f km/h", avgSpeedKmh))
            statItem(label: appLanguage.localized("최고 속도"), value: String(format: "%.1f km/h", maxSpeedKmh))
            statItem(label: appLanguage.localized("평균 케이던스"), value: record.formattedCadence)
            statItem(label: appLanguage.localized("총 고도 상승"), value: String(format: "%.0f m", elevationGain))
            statItem(label: appLanguage.localized("경로 포인트"), value: appLanguage.text("\(record.routePoints.count)개", "\(record.routePoints.count) pts"))
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(RBFont.metric(18))
                .foregroundStyle(RBColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                            .foregroundStyle(.white)
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

                HStack(spacing: 10) {
                    sensorPill(
                        title: appLanguage.localized("GPS 평균 오차"),
                        value: averageGPSAccuracyMeters.map { String(format: "±%.0f m", $0) } ?? appLanguage.localized("데이터 적음")
                    )
                    sensorPill(title: appLanguage.localized("경로 포인트"), value: appLanguage.text("\(record.routePoints.count)개", "\(record.routePoints.count) pts"))
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sensorPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(RBFont.metric(14))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        record.averageGPSAccuracyMeters
    }

    private var sensorQualityTitle: String {
        guard let accuracy = averageGPSAccuracyMeters else {
            return appLanguage.localized("센서 보정 중")
        }

        switch accuracy {
        case ...10:
            return appLanguage.localized("매우 안정적인 GPS")
        case ...25:
            return appLanguage.localized("안정적인 GPS")
        case ...50:
            return appLanguage.localized("보통 수준의 GPS")
        default:
            return appLanguage.localized("GPS 흔들림이 있었어요")
        }
    }

    private var sensorQualityDescription: String {
        guard let accuracy = averageGPSAccuracyMeters else {
            return appLanguage.localized("거리와 페이스는 GPS와 걸음 데이터를 함께 사용해 계산하고 있습니다. 경로 포인트가 더 쌓이면 정확도 판단이 더 선명해집니다.")
        }

        if appLanguage.isEnglish {
            return String(format: "Distance and pace combine GPS route data with step data. Cadence is calculated from steps, and the average GPS error for this run was about ±%.0f m.", accuracy)
        }

        return String(format: "거리와 페이스는 GPS 경로와 걸음 데이터를 함께 반영했고, 케이던스는 걸음 수 기반으로 계산했습니다. 이번 러닝의 평균 GPS 오차는 약 ±%.0fm입니다.", accuracy)
    }

    private var sensorQualityColor: Color {
        guard let accuracy = averageGPSAccuracyMeters else {
            return RBColor.accent
        }

        switch accuracy {
        case ...10:
            return RBColor.success
        case ...25:
            return RBColor.accent
        case ...50:
            return Color.orange
        default:
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
