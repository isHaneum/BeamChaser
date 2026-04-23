import SwiftUI
import MapKit
import UIKit

struct RunActiveView: View {
    private enum RunPage: Int, CaseIterable, Identifiable {
        case map
        case focus
        case splits

        var id: Int { rawValue }

        var previous: RunPage? {
            guard let page = RunPage(rawValue: rawValue - 1) else { return nil }
            return page
        }

        var next: RunPage? {
            guard let page = RunPage(rawValue: rawValue + 1) else { return nil }
            return page
        }
    }

    private struct RunningMiniMetric: Identifiable {
        let label: String
        let value: String
        let unit: String
        let tint: Color

        var id: String { label }
    }

    private struct SplitEntry: Identifiable {
        let kilometer: Int
        let paceSeconds: Double
        let deltaSeconds: Int?

        var id: Int { kilometer }
    }

    private struct CurrentSplitSnapshot {
        let distanceMeters: Double
        let duration: TimeInterval
        let paceSeconds: Double
    }

    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var healthKit: HealthKitService
    @EnvironmentObject var voiceGuide: VoiceGuideService
    @EnvironmentObject var nowPlayingService: NowPlayingService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var selectedPage: RunPage = .focus
    @State private var showGoalReachedAlert = false
    @State private var pauseBlinkOpacity: Double = 1.0
    @State private var didFinish = false
    @State private var finishedRecord: RunRecord?
    @State private var showDeviceConnection = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var splitCardBackground: Color {
        Color(red: 0.965, green: 0.965, blue: 0.955)
    }

    private var splitCardStroke: Color {
        Color.black.opacity(0.06)
    }

    private var splitPrimaryText: Color {
        Color.black.opacity(0.86)
    }

    private var splitSecondaryText: Color {
        Color.black.opacity(0.62)
    }

    private var splitTertiaryText: Color {
        Color.black.opacity(0.42)
    }

    private var splitMutedFill: Color {
        Color.black.opacity(0.06)
    }

    private var isDarkBackdropPage: Bool {
        true
    }

    private var pageForegroundColor: Color {
        isDarkBackdropPage ? .white : .black
    }

    private var secondaryForegroundColor: Color {
        isDarkBackdropPage ? Color.white.opacity(0.72) : Color.black.opacity(0.52)
    }

    private var tertiaryForegroundColor: Color {
        isDarkBackdropPage ? Color.white.opacity(0.34) : Color.black.opacity(0.14)
    }

    private var horizontalChromePadding: CGFloat {
        16
    }

    var body: some View {
        ZStack {
            screenBackground

            VStack(spacing: 0) {
                if !didFinish {
                    VStack(spacing: 14) {
                        pageIndicator
                        fixedPaceIndicator
                    }
                    .padding(.horizontal, horizontalChromePadding)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                }

                TabView(selection: $selectedPage) {
                    routeOverviewPage.tag(RunPage.map)
                    focusPage.tag(RunPage.focus)
                    splitsPage.tag(RunPage.splits)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if didFinish {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(isDarkBackdropPage ? .dark : .light)
        .safeAreaInset(edge: .bottom) {
            if !didFinish {
                controlDock
                    .padding(.horizontal, horizontalChromePadding)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showDeviceConnection) {
            NavigationStack {
                DeviceConnectionView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $finishedRecord) { record in
            NavigationStack {
                RunDetailView(
                    record: record,
                    onDone: closeFinishedRunFlow
                )
                .environmentObject(runSession)
            }
        }
        .onAppear {
            nowPlayingService.activate()

            #if targetEnvironment(simulator)
            locationService.enableSimulatorMode()
            locationService.startTracking_simulator()
            #else
            locationService.startTracking()
            #endif

            voiceGuide.announceRunStart()
        }
        .onDisappear {
            if !didFinish {
                locationService.simulatorStop()
                locationService.stopTracking()
                locationService.reset()
                Task { await runSession.healthKit.discardWorkout() }
                voiceGuide.reset()
            }

            runSession.resetSession()
        }
        .onChange(of: locationService.totalDistanceMeters) { _, newValue in
            guard runSession.runState == .running, !didFinish else { return }
            runSession.updatePace(distance: newValue)

            let currentPace = newValue > 0
                ? runSession.elapsedSeconds / (newValue / 1000.0)
                : 0

            voiceGuide.handleDistanceUpdate(
                totalDistanceMeters: newValue,
                currentPaceSecondsPerKm: currentPace
            )
        }
        .onChange(of: locationService.routePoints.count) { _, _ in
            guard runSession.runState == .running, !didFinish else { return }

            if let location = locationService.currentLocation {
                runSession.healthKit.addRouteData([location])
            }
        }
        .onChange(of: runSession.paceMaker.gapMeters) { _, newGap in
            guard runSession.runState == .running, !didFinish else { return }
            voiceGuide.handleGapUpdate(gapMeters: newGap)
        }
        .alert(appLanguage.localized("목표 달성!"), isPresented: $showGoalReachedAlert) {
            Button(appLanguage.localized("계속 달리기"), role: .cancel) {}
            Button(appLanguage.localized("종료하기")) { finishRun() }
        } message: {
            Text(appLanguage.localized("설정한 목표를 달성했습니다! 계속 달릴 수도 있습니다."))
        }
        .onChange(of: runSession.goalReached) { _, reached in
            if reached {
                showGoalReachedAlert = true
                voiceGuide.announceGoalReached()
            }
        }
    }

    private var screenBackground: some View {
        ZStack(alignment: .leading) {
            Color.black
                .ignoresSafeArea()

            musicBackground
                .opacity(selectedPage == .focus ? 1 : 0)

            mapBackgroundLayer
                .opacity(selectedPage == .map ? 1 : 0)
                .offset(x: selectedPage == .map ? 0 : -96)
        }
        .animation(.easeInOut(duration: 0.32), value: selectedPage)
    }

    @ViewBuilder
    private var musicBackground: some View {
        if let artwork = nowPlayingService.artworkImage {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .blur(radius: 18)
                .overlay(Color.black.opacity(0.28))
                .transition(.opacity)
        } else {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.15, blue: 0.17), Color(red: 0.06, green: 0.06, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var mapBackgroundLayer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RunMapView(presentationMode: .routeOverview, showsRecenterButton: false)
                    .allowsHitTesting(false)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                Color.black.opacity(0.20)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.32),
                        Color.black.opacity(0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .ignoresSafeArea()
    }

    private var routeOverviewPage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                heroRunningMetric(
                    value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                    unit: "km",
                    color: .white,
                    prominent: true
                )

                heroRunningMetric(
                    value: RunRecord.formatDuration(runSession.elapsedSeconds),
                    unit: nil,
                    color: Color.white.opacity(0.86)
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 74)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.16)

                VStack(spacing: 10) {
                    heroRunningMetric(
                        value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                        unit: "km",
                        color: .white,
                        prominent: true
                    )

                    heroRunningMetric(
                        value: RunRecord.formatDuration(runSession.elapsedSeconds),
                        unit: nil,
                        color: Color.white.opacity(0.9)
                    )
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: geometry.size.height * 0.18)

                VStack(spacing: 10) {
                    if nowPlayingService.hasNowPlaying {
                        Text(nowPlayingService.title)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(nowPlayingService.artist.isEmpty ? nowPlayingService.albumTitle : nowPlayingService.artist)
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    HStack(spacing: 42) {
                        musicTransportButton(systemName: "backward.fill") {
                            nowPlayingService.skipToPreviousTrack()
                        }

                        musicTransportButton(systemName: nowPlayingService.isPlaying ? "pause.fill" : "play.fill", isPrimary: true) {
                            nowPlayingService.togglePlayback()
                        }

                        musicTransportButton(systemName: "forward.fill") {
                            nowPlayingService.skipToNextTrack()
                        }
                    }
                }
                .padding(.bottom, 72)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func focusPageContent(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 18) {
            miniMetricsRow

            runSummaryBlock(compact: compact)

            nowPlayingCard(compact: compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func runSummaryBlock(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", locationService.totalDistanceMeters / 1000.0))
                    .font(RBFont.metric(compact ? 64 : 72))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("km")
                    .font(RBFont.label(compact ? 24 : 28))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Text(RunRecord.formatDuration(runSession.elapsedSeconds))
                .font(RBFont.metric(compact ? 22 : 26))
                .foregroundStyle(Color.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 2 : 8)
    }

    private var splitsPage: some View {
        VStack(spacing: 20) {
            Spacer()

            heroRunningMetric(
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                color: .white,
                prominent: true
            )

            heroRunningMetric(
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: nil,
                color: Color.white.opacity(0.84)
            )

            heroRunningMetric(
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km",
                color: Color.white.opacity(0.74),
                compact: true
            )

            HStack(spacing: 12) {
                ForEach([-10, -5, 5, 10], id: \.self) { delta in
                    Button {
                        adjustTargetPace(by: delta)
                    } label: {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(RBFont.label(16))
                            .foregroundStyle(.white)
                            .frame(width: 68, height: 46)
                            .background(Color.black.opacity(0.34))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fixedPaceIndicator: some View {
        ViewThatFits(in: .horizontal) {
            fullPaceIndicatorRow
            compactPaceIndicatorRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.26), radius: 18, y: 10)
    }

    private var fullPaceIndicatorRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(paceStatusColor)
                .frame(width: 8, height: 8)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(RunRecord.formatPace(locationService.currentPaceSecondsPerKm))
                    .font(RBFont.metric(22))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("/km")
                    .font(RBFont.caption(12))
                    .foregroundStyle(Color.white.opacity(0.56))
            }

            dividerBar

            topBarStat(value: heartRateText, unit: "bpm", tint: Color.red.opacity(0.86), emphasizeIcon: true)

            dividerBar

            topBarStat(value: cadenceText, unit: "spm", tint: Color.white.opacity(0.82))

            Spacer(minLength: 0)

            dividerBar

            Text(String(format: "+%.0fm", currentElevationGainMeters))
                .font(RBFont.label(17))
                .foregroundStyle(RBColor.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var compactPaceIndicatorRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(paceStatusColor)
                .frame(width: 8, height: 8)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(RunRecord.formatPace(locationService.currentPaceSecondsPerKm))
                    .font(RBFont.metric(20))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("/km")
                    .font(RBFont.caption(11))
                    .foregroundStyle(Color.white.opacity(0.56))
            }

            dividerBar

            topBarStat(value: heartRateText, unit: "bpm", tint: Color.red.opacity(0.86), emphasizeIcon: true)

            dividerBar

            topBarStat(value: cadenceText, unit: "spm", tint: Color.white.opacity(0.82))
        }
    }

    private var dividerBar: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 18)
    }

    private func topBarStat(value: String, unit: String, tint: Color, emphasizeIcon: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            if emphasizeIcon {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text(value)
                .font(RBFont.label(15))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(unit)
                .font(RBFont.caption(11))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func compactMapMetric(value: String, unit: String?, subdued: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: subdued ? 28 : 40, weight: subdued ? .semibold : .bold, design: .rounded))
                .foregroundStyle(subdued ? Color.black.opacity(0.48) : Color.black.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if let unit {
                Text(unit)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(Color.black.opacity(0.34))
            }
        }
    }

    private func heroRunningMetric(
        value: String,
        unit: String?,
        color: Color,
        prominent: Bool = false,
        compact: Bool = false
    ) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: prominent ? 72 : (compact ? 34 : 52), weight: prominent ? .heavy : .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .monospacedDigit()

            if let unit {
                Text(unit)
                    .font(.system(size: prominent ? 22 : 18, weight: .medium, design: .default))
                    .foregroundStyle(color.opacity(0.58))
            }
        }
        .shadow(color: color == .white ? Color.black.opacity(0.18) : .clear, radius: 10, y: 5)
    }

    private var currentElevationGainMeters: Double {
        let points = locationService.routePoints
        guard points.count >= 2 else { return 0 }

        var gain: Double = 0
        for index in 1..<points.count {
            let diff = points[index].altitude - points[index - 1].altitude
            if diff > 0 { gain += diff }
        }
        return gain
    }

    @ViewBuilder
    private var focusBackground: some View {
        if let artwork = nowPlayingService.artworkImage {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .saturation(1.08)
                .blur(radius: 8)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.14),
                            Color.black.opacity(0.24),
                            Color.black.opacity(0.38)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.12, blue: 0.10), Color(red: 0.05, green: 0.05, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Capsule()
                        .fill(RBColor.accent.opacity(0.18))
                        .frame(width: 220, height: 220)
                        .blur(radius: 18)

                    Capsule()
                        .fill(RBColor.success.opacity(0.12))
                        .frame(width: 160, height: 160)
                        .blur(radius: 12)
                }
                .rotationEffect(.degrees(-18))
            }
        }
    }

    private var topOverlay: some View {
            VStack(spacing: 10) {
            HStack(spacing: 8) {
                gpsSignalIndicator
                deviceConnectionChip
                Spacer()

                if let goal = runSession.runGoal, goal.type != .none {
                    goalProgressBadge(goal)
                }
            }

            paceStatusBanner
        }
    }

    private var gpsSignalIndicator: some View {
        let accuracy = locationService.currentLocation?.horizontalAccuracy ?? -1
        let (level, color): (String, Color) = {
            if accuracy < 0 { return (appLanguage.text("없음", "No GPS"), RBColor.danger) }
            if accuracy < 10 { return (appLanguage.text("강함", "Strong"), RBColor.success) }
            if accuracy < 20 { return (appLanguage.text("보통", "Mid"), .yellow) }
            return (appLanguage.text("약함", "Weak"), RBColor.danger)
        }()
        let bars: Int = {
            if accuracy < 0 { return 0 }
            if accuracy < 10 { return 3 }
            if accuracy < 20 { return 2 }
            return 1
        }()

        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < bars ? color : Color.white.opacity(0.18))
                    .frame(width: 3, height: CGFloat(6 + index * 3))
            }

            Text(level)
                .font(RBFont.caption(9))
                .foregroundStyle(color)
                    .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.82))
        .clipShape(Capsule())
    }

    private var deviceConnectionChip: some View {
        Button {
            showDeviceConnection = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(bleService.isConnected ? RBColor.success : RBColor.danger)
                    .frame(width: 8, height: 8)

                Text(bleService.connectedDeviceName ?? "BeamChaser")
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 110, alignment: .leading)

                if let status = bleService.deviceStatus {
                    Text("\(status.batteryPercent)%")
                        .font(RBFont.metric(11))
                        .foregroundStyle(bleService.isConnected ? RBColor.success : RBColor.danger)
                } else if !bleService.isConnected {
                    Text(appLanguage.text("미연결", "Offline"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.danger)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial.opacity(0.82))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func goalProgressBadge(_ goal: RunGoal) -> some View {
        let progress: Double = {
            switch goal.type {
            case .distance:
                guard let targetKm = goal.targetDistanceKm, targetKm > 0 else { return 0 }
                return min(1.0, locationService.totalDistanceMeters / 1000.0 / targetKm)
            case .time:
                guard let targetMin = goal.targetTimeMinutes, targetMin > 0 else { return 0 }
                return min(1.0, runSession.elapsedSeconds / Double(targetMin * 60))
            case .combined:
                let distanceProgress: Double = {
                    guard let targetKm = goal.targetDistanceKm, targetKm > 0 else { return 0 }
                    return min(1.0, locationService.totalDistanceMeters / 1000.0 / targetKm)
                }()
                let timeProgress: Double = {
                    guard let targetMin = goal.targetTimeMinutes, targetMin > 0 else { return 0 }
                    return min(1.0, runSession.elapsedSeconds / Double(targetMin * 60))
                }()
                return max(distanceProgress, timeProgress)
            case .none:
                return 0
            }
        }()

        return HStack(spacing: 4) {
            Image(systemName: goal.type.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(String(format: "%.0f%%", progress * 100))
                .font(RBFont.metric(11))
        }
        .foregroundStyle(progress >= 1.0 ? RBColor.success : RBColor.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.82))
        .clipShape(Capsule())
    }

    private var paceStatusBanner: some View {
        let hasTarget = runSession.paceMaker.target != nil
        let status = runSession.paceMaker.paceStatus
        let bannerColor = hasTarget ? paceStatusColor : RBColor.accent
        let bannerTitle = hasTarget ? status.label : appLanguage.text("자유 러닝", "Free Run")

        return HStack(spacing: 12) {
            Image(systemName: hasTarget ? status.icon : "figure.run")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(RBFont.label(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let segment = currentIntervalSegment {
                    Text("\(segment.name) · \(segment.formattedPace)")
                        .font(RBFont.caption(10))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(RunRecord.formatPace(locationService.currentPaceSecondsPerKm))
                    .font(RBFont.metric(18))
                    .foregroundStyle(.white)
                Text("/km")
                    .font(RBFont.caption(10))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            if hasTarget {
                Divider()
                    .frame(height: 26)
                    .overlay(Color.white.opacity(0.18))

                VStack(alignment: .trailing, spacing: 1) {
                    Text(runSession.paceMaker.formattedGap)
                        .font(RBFont.metric(17))
                        .foregroundStyle(.white)
                    Text(runSession.paceMaker.formattedTimeGap)
                        .font(RBFont.caption(10))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(bannerColor.opacity(0.88))
        )
        .shadow(color: bannerColor.opacity(0.34), radius: 12, y: 4)
    }

    private var pageIndicator: some View {
        let activeColor = pageForegroundColor
        let inactiveColor = tertiaryForegroundColor

        return HStack(spacing: 8) {
            ForEach(RunPage.allCases) { page in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        selectedPage = page
                    }
                } label: {
                    Circle()
                        .fill(selectedPage == page ? activeColor : inactiveColor)
                        .frame(width: selectedPage == page ? 8 : 6, height: selectedPage == page ? 8 : 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pageNavigationBar: some View {
        HStack(spacing: 12) {
            pageStepButton(systemName: "chevron.left", target: selectedPage.previous)

            pageIndicator
                .frame(maxWidth: .infinity)

            pageStepButton(systemName: "chevron.right", target: selectedPage.next)
        }
    }

    private func pageStepButton(systemName: String, target: RunPage?) -> some View {
        Button {
            guard let target else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedPage = target
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(target == nil ? Color.white.opacity(0.24) : .white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(target == nil ? 0.06 : 0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
    }

    private var controlDock: some View {
        Group {
            if runSession.runState == .paused {
                pausedControlDock
            } else {
                runningControlDock
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var runningControlDock: some View {
        wideControlButton(
            title: appLanguage.text("러닝 일시정지", "Pause Run"),
            icon: "pause.fill",
            fill: AnyShapeStyle(RBColor.accentGradient)
        ) {
            runSession.pauseRun()
        }
        .frame(maxWidth: 420)
    }

    private var pausedControlDock: some View {
        VStack(spacing: 12) {
            Text(appLanguage.text("러닝이 일시정지되었습니다", "Run paused"))
                .font(RBFont.caption(12))
                .foregroundStyle(Color.white.opacity(0.68))

            HStack(spacing: 12) {
                Button {
                    finishRun()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(appLanguage.text("종료", "Finish"))
                            .font(RBFont.label(15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    runSession.resumeRun()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(appLanguage.text("계속 달리기", "Resume Run"))
                            .font(RBFont.label(15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RBColor.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(Color.black.opacity(0.46))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
        .frame(maxWidth: .infinity)
    }

    private func wideControlButton(
        title: String,
        icon: String,
        fill: AnyShapeStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(RBFont.label(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var topMiniMetrics: [RunningMiniMetric] {
        [
            RunningMiniMetric(
                label: appLanguage.text("페이스", "Pace"),
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km",
                tint: .white
            ),
            RunningMiniMetric(
                label: appLanguage.text("심박", "BPM"),
                value: heartRateText,
                unit: "bpm",
                tint: healthKit.currentHeartRate > 0 ? .red : Color.white.opacity(0.86)
            ),
            RunningMiniMetric(
                label: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: currentCadenceSpm > 0 ? cadenceColor : Color.white.opacity(0.86)
            )
        ]
    }

    /// 3개 지표를 한 줄에 모두 표시하는 가로 바
    private var miniMetricsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(topMiniMetrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Divider()
                        .frame(width: 1, height: 28)
                        .overlay(Color.white.opacity(0.15))
                }
                VStack(spacing: 1) {
                    Text(metric.label)
                        .font(RBFont.caption(9))
                        .foregroundStyle(Color.white.opacity(0.52))
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(metric.value)
                            .font(RBFont.metric(15))
                            .foregroundStyle(metric.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(metric.unit)
                            .font(RBFont.caption(9))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func nowPlayingCard(compact: Bool) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous)
                    .fill(Color.white.opacity(0.12))

                if let artwork = nowPlayingService.artworkImage {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: compact ? 28 : 34, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .frame(width: compact ? 72 : 92, height: compact ? 72 : 92)

            VStack(spacing: compact ? 3 : 4) {
                let displayTitle = nowPlayingService.title.isEmpty
                    ? appLanguage.text("재생 중인 음악 없음", "No Track Playing")
                    : nowPlayingService.title
                Text(displayTitle)
                    .font(RBFont.label(compact ? 16 : 18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                let subtitle = nowPlayingService.artist.isEmpty
                    ? (nowPlayingService.albumTitle.isEmpty
                        ? appLanguage.text("Apple Music 또는 시스템 오디오", "Apple Music or system audio")
                        : nowPlayingService.albumTitle)
                    : nowPlayingService.artist
                Text(subtitle)
                    .font(RBFont.caption(compact ? 12 : 13))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: compact ? 12 : 14) {
                musicTransportButton(systemName: "backward.fill", compact: compact) {
                    nowPlayingService.skipToPreviousTrack()
                }

                musicTransportButton(systemName: nowPlayingService.isPlaying ? "pause.fill" : "play.fill", isPrimary: true, compact: compact) {
                    nowPlayingService.togglePlayback()
                }

                musicTransportButton(systemName: "forward.fill", compact: compact) {
                    nowPlayingService.skipToNextTrack()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 14 : 16)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func musicTransportButton(
        systemName: String,
        isPrimary: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? 30 : 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isPrimary ? 56 : 44, height: isPrimary ? 56 : 44)
                .background(isPrimary ? Color.white.opacity(0.16) : Color.black.opacity(0.18))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isPrimary ? 0.16 : 0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var targetPaceCard: some View {
        splitCard {
            VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(appLanguage.text("목표 페이스", "Target Pace"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(splitTertiaryText)
                    .tracking(1)

                Spacer()

                Text(currentTargetPace.formatted)
                    .font(RBFont.metric(18))
                    .foregroundStyle(RBColor.accent)
            }

            HStack(spacing: 10) {
                targetPaceAdjustButton(title: "-10", deltaSeconds: -10)
                targetPaceAdjustButton(title: "-5", deltaSeconds: -5)
                targetPaceAdjustButton(title: "+5", deltaSeconds: 5)
                targetPaceAdjustButton(title: "+10", deltaSeconds: 10)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetTargetPaces, id: \.formatted) { target in
                        Button {
                            setTargetPace(target)
                        } label: {
                            Text(target.formatted)
                                .font(RBFont.caption(11))
                                .foregroundStyle(currentTargetPace.totalSecondsPerKm == target.totalSecondsPerKm ? splitPrimaryText : splitSecondaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    currentTargetPace.totalSecondsPerKm == target.totalSecondsPerKm
                                        ? AnyShapeStyle(RBColor.accent.opacity(0.22))
                                        : AnyShapeStyle(splitMutedFill)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        }
    }

    private func targetPaceAdjustButton(title: String, deltaSeconds: Int) -> some View {
        Button {
            adjustTargetPace(by: deltaSeconds)
        } label: {
            Text(title)
                .font(RBFont.label(14))
                .foregroundStyle(splitPrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(splitMutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var currentSplitCard: some View {
        let snapshot = splitSnapshot.current
        let progress = min(max(snapshot.distanceMeters / 1000.0, 0), 1)

        return splitCard {
            VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(appLanguage.text("현재 스플릿", "Current Split"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(splitTertiaryText)
                    .tracking(1)

                Spacer()

                Text(String(format: "%.2fkm", snapshot.distanceMeters / 1000.0))
                    .font(RBFont.metric(16))
                    .foregroundStyle(splitPrimaryText)
            }

            HStack(spacing: 16) {
                splitMetricBlock(
                    title: appLanguage.text("페이스", "Pace"),
                    value: RunRecord.formatPace(snapshot.paceSeconds),
                    unit: "/km"
                )

                splitMetricBlock(
                    title: appLanguage.text("시간", "Time"),
                    value: RunRecord.formatDuration(snapshot.duration),
                    unit: ""
                )
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(splitMutedFill)
                        .frame(height: 9)

                    Capsule()
                        .fill(RBColor.accent)
                        .frame(width: max(10, geo.size.width * progress), height: 9)
                }
            }
            .frame(height: 9)
        }
        }
    }

    private var splitsListCard: some View {
        splitCard {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appLanguage.text("1km 스플릿", "1km Splits"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(splitTertiaryText)
                    .tracking(1)
                Spacer()
            }

            VStack(spacing: 10) {
                if splitSnapshot.completed.isEmpty {
                    splitRow(
                        title: "1km",
                        pace: "--:--",
                        delta: nil
                    )
                } else {
                    ForEach(splitSnapshot.completed) { split in
                        splitRow(
                            title: "\(split.kilometer)km",
                            pace: RunRecord.formatPace(split.paceSeconds),
                            delta: split.deltaSeconds
                        )
                    }
                }
            }
        }
        }
    }

    private func splitRow(title: String, pace: String, delta: Int?) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(RBFont.label(13))
                .foregroundStyle(splitSecondaryText)
                .frame(width: 44, alignment: .leading)

            Spacer()

            Text(pace)
                .font(RBFont.metric(16))
                .foregroundStyle(splitPrimaryText)

            if let delta {
                Text(formattedDelta(delta))
                    .font(RBFont.caption(11))
                    .foregroundStyle(delta <= 0 ? RBColor.success : RBColor.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((delta <= 0 ? RBColor.success : RBColor.danger).opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(splitMutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deviceIdentityCard: some View {
        splitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(appLanguage.text("기기 연결", "Device"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(splitTertiaryText)
                        .tracking(1)

                    Spacer()

                    Text(bleService.isConnected ? appLanguage.text("연결됨", "Connected") : appLanguage.text("미연결", "Disconnected"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.danger)
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(bleService.isConnected ? RBColor.success : RBColor.danger)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(bleService.connectedDeviceName ?? "BeamChaser")
                            .font(RBFont.label(14))
                            .foregroundStyle(splitPrimaryText)
                            .lineLimit(1)

                        Text(deviceIdentityStatusText)
                            .font(RBFont.caption(11))
                            .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.danger)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        showDeviceConnection = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(splitPrimaryText)
                            .frame(width: 42, height: 42)
                            .background(splitMutedFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deviceIdentityStatusText: String {
        if let status = bleService.deviceStatus {
            return appLanguage.text("배터리 \(status.batteryPercent)%", "Battery \(status.batteryPercent)%")
        }

        return appLanguage.text("상태 정보를 확인하세요", "Check device status")
    }

    private func splitCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(splitCardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(splitCardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func splitMetricBlock(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RBFont.caption(10))
                .foregroundStyle(splitTertiaryText)
                .tracking(1)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(RBFont.metric(20))
                    .foregroundStyle(splitPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .font(RBFont.caption(12))
                        .foregroundStyle(splitSecondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentTargetPace: PaceTarget {
        runSession.currentRecord?.targetPace
            ?? runSession.paceMaker.target
            ?? PaceTarget(minutesPerKm: 5, secondsPerKm: 30)
    }

    private var presetTargetPaces: [PaceTarget] {
        [
            PaceTarget(minutesPerKm: 4, secondsPerKm: 30),
            PaceTarget(minutesPerKm: 5, secondsPerKm: 0),
            PaceTarget(minutesPerKm: 5, secondsPerKm: 30),
            PaceTarget(minutesPerKm: 6, secondsPerKm: 0),
            PaceTarget(minutesPerKm: 6, secondsPerKm: 30)
        ]
    }

    private var splitSnapshot: (completed: [SplitEntry], current: CurrentSplitSnapshot) {
        let totalDistance = max(locationService.totalDistanceMeters, 0)
        let elapsed = max(runSession.elapsedSeconds, 0)
        let targetSeconds = runSession.paceMaker.target?.totalSecondsPerKm

        let fallbackCurrent = CurrentSplitSnapshot(
            distanceMeters: totalDistance,
            duration: elapsed,
            paceSeconds: paceSeconds(distanceMeters: totalDistance, duration: elapsed)
        )

        let points = locationService.routePoints
        guard points.count >= 2 else {
            return ([], fallbackCurrent)
        }

        var cumulativeDistances = Array(repeating: 0.0, count: points.count)
        for index in 1..<points.count {
            cumulativeDistances[index] = cumulativeDistances[index - 1] + distanceBetween(points[index - 1], points[index])
        }

        var splits: [SplitEntry] = []
        var previousSplitTime = points[0].timestamp
        var searchIndex = 1
        let totalTrackedDistance = cumulativeDistances.last ?? 0

        while Double(splits.count + 1) * 1000 <= totalTrackedDistance, searchIndex < points.count {
            let threshold = Double(splits.count + 1) * 1000

            while searchIndex < points.count && cumulativeDistances[searchIndex] < threshold {
                searchIndex += 1
            }

            guard searchIndex < points.count else { break }

            let previousIndex = max(0, searchIndex - 1)
            let previousDistance = cumulativeDistances[previousIndex]
            let nextDistance = cumulativeDistances[searchIndex]
            let segmentDistance = max(nextDistance - previousDistance, 0.001)
            let ratio = min(max((threshold - previousDistance) / segmentDistance, 0), 1)
            let segmentDuration = points[searchIndex].timestamp.timeIntervalSince(points[previousIndex].timestamp)
            let crossingTime = points[previousIndex].timestamp.addingTimeInterval(segmentDuration * ratio)
            let splitDuration = crossingTime.timeIntervalSince(previousSplitTime)

            splits.append(
                SplitEntry(
                    kilometer: splits.count + 1,
                    paceSeconds: splitDuration,
                    deltaSeconds: targetSeconds.map { Int((splitDuration - $0).rounded()) }
                )
            )

            previousSplitTime = crossingTime
        }

        let lastCompletedDistance = Double(splits.count) * 1000
        let partialDistance = max(totalDistance - lastCompletedDistance, 0)
        let completedDuration = splits.reduce(0.0) { $0 + $1.paceSeconds }
        let partialDuration = max(elapsed - completedDuration, 0)

        let current = CurrentSplitSnapshot(
            distanceMeters: partialDistance,
            duration: partialDuration,
            paceSeconds: paceSeconds(distanceMeters: partialDistance, duration: partialDuration)
        )

        return (splits, current)
    }

    private var currentIntervalSegment: IntervalSegment? {
        guard let interval = runSession.intervalProgram, !interval.segments.isEmpty else { return nil }
        let index = min(runSession.currentIntervalIndex, interval.segments.count - 1)
        return interval.segments[index]
    }

    private var currentCadenceSpm: Double {
        locationService.currentCadenceSpm
    }

    private var cadenceColor: Color {
        guard currentCadenceSpm > 0 else { return RBColor.textSecondary }

        switch currentCadenceSpm {
        case ..<160:
            return .yellow
        case 160...180:
            return RBColor.success
        default:
            return RBColor.accent
        }
    }

    private var cadenceText: String {
        guard currentCadenceSpm > 0 else { return "--" }
        return String(Int(currentCadenceSpm.rounded()))
    }

    private var heartRateText: String {
        guard healthKit.isWorkoutActive, healthKit.hasLiveHeartRate, healthKit.currentHeartRate > 0 else { return "--" }
        return String(Int(healthKit.currentHeartRate.rounded()))
    }

    private var paceStatusColor: Color {
        switch runSession.paceMaker.paceStatus {
        case .ahead:
            return RBColor.success
        case .onPace:
            return RBColor.accent
        case .behind:
            return RBColor.danger
        }
    }

    private func adjustTargetPace(by deltaSeconds: Int) {
        let totalSeconds = Int(currentTargetPace.totalSecondsPerKm) + deltaSeconds
        let clamped = min(max(totalSeconds, 180), 540)
        setTargetPace(PaceTarget(minutesPerKm: clamped / 60, secondsPerKm: clamped % 60))
    }

    private func setTargetPace(_ target: PaceTarget) {
        runSession.updateTargetPace(target)
    }

    private func formattedDelta(_ delta: Int) -> String {
        let prefix = delta <= 0 ? "" : "+"
        return "\(prefix)\(delta)s"
    }

    private func distanceBetween(_ left: RoutePoint, _ right: RoutePoint) -> Double {
        CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude))
    }

    private func paceSeconds(distanceMeters: Double, duration: TimeInterval) -> Double {
        guard distanceMeters > 1, duration > 0 else { return 0 }
        return duration / (distanceMeters / 1000.0)
    }

    private func finishRun() {
        guard !didFinish else { return }
        didFinish = true
        voiceGuide.announceRunFinish()
        locationService.simulatorStop()

        let routePoints = locationService.routePoints
        let totalDistance = locationService.totalDistanceMeters
        let averageCadenceSpm = runSession.elapsedSeconds > 0
            ? Int((Double(locationService.sessionStepCount) / runSession.elapsedSeconds * 60.0).rounded())
            : nil
        let averageHeartRateBpm = runSession.healthKit.averageHeartRate > 0
            ? Int(runSession.healthKit.averageHeartRate.rounded())
            : nil

        runSession.finishRun(
            routePoints: routePoints,
            totalDistance: totalDistance,
            averageCadenceSpm: averageCadenceSpm,
            averageHeartRateBpm: averageHeartRateBpm
        )

        finishedRecord = runSession.currentRecord
        locationService.stopTracking()
        locationService.reset()
    }

    private func closeFinishedRunFlow() {
        finishedRecord = nil
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RunActiveView()
            .environmentObject(RunSessionManager())
            .environmentObject(LocationService())
            .environmentObject(BLEService())
            .environmentObject(HealthKitService())
            .environmentObject(VoiceGuideService())
            .environmentObject(NowPlayingService())
    }
}
