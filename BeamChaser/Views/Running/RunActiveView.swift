import SwiftUI
import MapKit
import UIKit

enum RunActiveLayoutHarness {
    static let topOverlayOuterPadding = ComponentTokens.RunActive.topOverlayOuterPadding
    static let topOverlayInnerSpacing = ComponentTokens.RunActive.topOverlayInnerSpacing
    static let topIndicatorHeight = ComponentTokens.RunActive.topIndicatorHeight
    static let modeToggleOuterHeight = ComponentTokens.RunActive.modeToggleOuterHeight
    static let metricBarOuterHeight = ComponentTokens.RunActive.metricBarOuterHeight

    static func topOverlayHeight(compact: Bool) -> CGFloat {
        ComponentTokens.RunActive.topOverlayHeight(compact: compact)
    }
}

private struct RunActiveViewportLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    let compact: Bool
    let contentWidth: CGFloat
    let topOverlayTop: CGFloat
    let topOverlayHeight: CGFloat
    let bottomOverlayBottom: CGFloat
    let bottomControlHeight: CGFloat
    let pageTopPadding: CGFloat
    let pageBottomPadding: CGFloat
    let availableHeight: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets, isPaused: Bool) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
        compact = LayoutTokens.isCompactRunLayout(size: size, safeAreaInsets: safeAreaInsets)
        contentWidth = LayoutTokens.contentWidth(for: size.width)
        topOverlayTop = ComponentTokens.RunActive.topOverlayTop(safeTop: safeAreaInsets.top)
        topOverlayHeight = ComponentTokens.RunActive.topOverlayHeight(compact: compact)
        bottomOverlayBottom = ComponentTokens.RunActive.bottomOverlayBottom(safeBottom: safeAreaInsets.bottom)
        bottomControlHeight = ComponentTokens.RunActive.bottomControlHeight(isPaused: isPaused, compact: compact)
        pageTopPadding = ComponentTokens.RunActive.pageTopPadding(safeTop: safeAreaInsets.top, compact: compact)
        pageBottomPadding = ComponentTokens.RunActive.pageBottomPadding(
            safeBottom: safeAreaInsets.bottom,
            isPaused: isPaused,
            compact: compact
        )
        availableHeight = max(0, size.height - pageTopPadding - pageBottomPadding)
    }
}

private struct RunPacePage<Header: View, SecondaryMetrics: View, TargetPanel: View, ClimateGuidance: View>: View {
    let layout: RunActiveViewportLayout
    @ViewBuilder let header: () -> Header
    @ViewBuilder let secondaryMetrics: () -> SecondaryMetrics
    @ViewBuilder let targetPanel: () -> TargetPanel
    @ViewBuilder let climateGuidance: () -> ClimateGuidance

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: layout.compact ? ComponentTokens.RunSurface.verticalSpacingMedium : ComponentTokens.RunSurface.verticalSpacingLarge) {
                Spacer(minLength: layout.compact ? 4 : 10)

                header()
                    .frame(width: layout.contentWidth)

                secondaryMetrics()
                    .frame(width: layout.contentWidth)

                targetPanel()
                    .frame(width: layout.contentWidth)

                climateGuidance()
                    .frame(width: layout.contentWidth)

                Spacer(minLength: layout.compact ? 4 : 10)
            }
            .frame(minHeight: layout.availableHeight)
            .padding(.top, layout.pageTopPadding)
            .padding(.bottom, layout.pageBottomPadding)
            .frame(width: layout.size.width)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct RunAudioPage<Stats: View, AlertStatus: View, NowPlaying: View, Controls: View>: View {
    let layout: RunActiveViewportLayout
    @ViewBuilder let stats: () -> Stats
    @ViewBuilder let alertStatus: () -> AlertStatus
    @ViewBuilder let nowPlaying: () -> NowPlaying
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: layout.compact ? ComponentTokens.RunSurface.verticalSpacingMedium : ComponentTokens.RunSurface.verticalSpacingLarge) {
                Spacer(minLength: layout.compact ? 4 : 10)

                stats()
                    .frame(width: layout.contentWidth)

                alertStatus()
                    .frame(width: layout.contentWidth)

                Spacer(minLength: layout.compact ? 8 : 16)

                VStack(spacing: layout.compact ? ComponentTokens.RunSurface.verticalSpacingMedium : ComponentTokens.RunSurface.verticalSpacingLarge) {
                    nowPlaying()
                        .frame(width: layout.contentWidth)

                    controls()
                        .frame(width: layout.contentWidth)
                }

                Spacer(minLength: layout.compact ? 4 : 10)
            }
            .frame(minHeight: layout.availableHeight)
            .padding(.top, layout.pageTopPadding + ComponentTokens.RunSurface.verticalSpacingSmall)
            .padding(.bottom, layout.pageBottomPadding)
            .frame(width: layout.size.width)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct RunLaserPage<Content: View>: View {
    let layout: RunActiveViewportLayout
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: ComponentTokens.RunSurface.verticalSpacingLarge) {
                content()
                    .frame(width: layout.contentWidth)
            }
            .frame(width: layout.size.width)
            .padding(.top, layout.pageTopPadding + ComponentTokens.RunSurface.verticalSpacingSmall)
            .padding(.bottom, layout.pageBottomPadding + ComponentTokens.RunSurface.verticalSpacingSmall)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct RunRouteMapPage<MapContent: View, MetricsOverlay: View, EmptyState: View>: View {
    let layout: RunActiveViewportLayout
    let hasRoute: Bool
    @ViewBuilder let mapContent: () -> MapContent
    @ViewBuilder let metricsOverlay: () -> MetricsOverlay
    @ViewBuilder let emptyState: () -> EmptyState

    var body: some View {
        ZStack {
            mapContent()
                .frame(width: layout.size.width, height: layout.size.height)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                metricsOverlay()
                    .frame(width: layout.contentWidth)

                Spacer(minLength: 0)
            }
            .padding(.top, layout.pageTopPadding + ComponentTokens.RunSurface.verticalSpacingSmall)
            .padding(.bottom, layout.pageBottomPadding)
            .frame(width: layout.size.width, height: layout.size.height)
            .allowsHitTesting(false)

            if !hasRoute {
                VStack {
                    Spacer(minLength: 0)
                    emptyState()
                        .frame(width: layout.contentWidth)
                    Spacer(minLength: 0)
                }
                .padding(.top, layout.pageTopPadding)
                .padding(.bottom, layout.pageBottomPadding)
                .frame(width: layout.size.width, height: layout.size.height)
                .allowsHitTesting(false)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct RunPageIndicatorDots: View {
    let pages: [RunActiveView.RunPage]
    let selectedPage: RunActiveView.RunPage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Capsule()
                    .fill(selectedPage == page ? Color.white : Color.white.opacity(0.32))
                    .frame(width: selectedPage == page ? 18 : 7, height: 7)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: ComponentTokens.RunActive.topIndicatorHeight)
        .background(Color.black.opacity(0.54))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }
}

private struct RunMetricsHUD: View {
    let items: [RunMetricBarItem]
    let compact: Bool

    var body: some View {
        RunMetricBar(items: items, compact: compact)
    }
}

private struct RunBottomControl<RunningControl: View, PausedControl: View>: View {
    let isPaused: Bool
    let contentWidth: CGFloat
    let runningHeight: CGFloat
    let pausedHeight: CGFloat
    @ViewBuilder let runningControl: () -> RunningControl
    @ViewBuilder let pausedControl: () -> PausedControl

    var body: some View {
        Group {
            if isPaused {
                pausedControl()
                    .frame(width: contentWidth)
                    .frame(maxHeight: pausedHeight)
            } else {
                runningControl()
                    .frame(width: contentWidth, height: runningHeight)
            }
        }
    }
}

private enum RunClimateGuidanceState: Equatable {
    case stable
    case caution
    case highRisk

    var tint: Color {
        switch self {
        case .stable:
            return ColorTokens.Run.climateStable
        case .caution:
            return ColorTokens.Run.climateCaution
        case .highRisk:
            return ColorTokens.Run.climateRisk
        }
    }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .stable:
            return appLanguage.text("기후 안정", "Climate steady")
        case .caution:
            return appLanguage.text("기후 주의", "Climate caution")
        case .highRisk:
            return appLanguage.text("기후 위험", "Climate risk")
        }
    }

    func guidance(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .stable:
            return appLanguage.text("목표 페이스 유지", "Hold target pace")
        case .caution:
            return appLanguage.text("+5초/km 여유 권장", "Allow +5 sec/km")
        case .highRisk:
            return appLanguage.text("+10초/km 완화 권장", "Ease +10 sec/km")
        }
    }
}

struct RunActiveView: View {
    fileprivate enum RunPage: Int, CaseIterable, Identifiable {
        case map
        case audio
        case control

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

    private struct RunPageLayout {
        let width: CGFloat
        let height: CGFloat
        let contentWidth: CGFloat
        let compact: Bool
        let musicSummaryTopPadding: CGFloat
        let musicBottomPadding: CGFloat
        let metricsTopPadding: CGFloat
        let metricsBottomPadding: CGFloat
        let dockBottomPadding: CGFloat
    }

    private struct RunMetricLine: View {
        let value: String
        let unit: String
        let valueSize: CGFloat
        let unitSize: CGFloat
        let valueColor: Color
        let unitColor: Color

        var body: some View {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: valueSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(unit)
                    .font(.system(size: unitSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(unitColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private struct RunMapPage<Content: View>: View {
        let layout: RunPageLayout
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .frame(width: layout.width, height: layout.height)
                .clipped()
        }
    }

    private struct RunMusicPage<Background: View, Summary: View, Card: View, Controls: View>: View {
        let layout: RunPageLayout
        @ViewBuilder let background: () -> Background
        @ViewBuilder let summary: () -> Summary
        @ViewBuilder let card: () -> Card
        @ViewBuilder let controls: () -> Controls

        var body: some View {
            ZStack {
                background()

                summary()
                    .frame(width: layout.contentWidth)
                    .padding(.top, layout.musicSummaryTopPadding)
                    .frame(width: layout.width, height: layout.height, alignment: .top)

                VStack(spacing: layout.compact ? 18 : 22) {
                    card()
                        .frame(width: layout.contentWidth)

                    controls()
                        .frame(width: layout.contentWidth)
                }
                .padding(.bottom, layout.musicBottomPadding)
                .frame(width: layout.width, height: layout.height, alignment: .bottom)
            }
            .frame(width: layout.width, height: layout.height)
            .clipped()
        }
    }

    private struct RunMetricsPage<Background: View, Content: View>: View {
        let layout: RunPageLayout
        @ViewBuilder let background: () -> Background
        @ViewBuilder let content: () -> Content

        var body: some View {
            ZStack {
                background()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: layout.compact ? 16 : 20) {
                        content()
                    }
                    .frame(width: layout.contentWidth)
                    .padding(.top, layout.metricsTopPadding)
                    .padding(.bottom, layout.metricsBottomPadding)
                    .frame(width: layout.width)
                }
            }
            .frame(width: layout.width, height: layout.height)
            .clipped()
        }
    }

    private struct RunTopHUD<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private struct RunPauseDock<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .frame(maxWidth: .infinity)
        }
    }

    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var healthKit: HealthKitService
    @EnvironmentObject var voiceGuide: VoiceGuideService
    @EnvironmentObject var nowPlayingService: NowPlayingService
    @EnvironmentObject private var appNavigation: AppNavigationModel
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var selectedPage: RunPage = .control
    @State private var showGoalReachedAlert = false
    @State private var pauseBlinkOpacity: Double = 1.0
    @State private var didFinish = false
    @State private var hasPreparedRunFinish = false
    @State private var isSavingRun = false
    @State private var runSaveErrorMessage: String?
    @State private var showDeviceConnection = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var splitCardBackground: Color {
        ColorTokens.Split.cardBackground
    }

    private var splitCardStroke: Color {
        ColorTokens.Split.stroke
    }

    private var splitPrimaryText: Color {
        ColorTokens.Split.primaryText
    }

    private var splitSecondaryText: Color {
        ColorTokens.Split.secondaryText
    }

    private var splitTertiaryText: Color {
        ColorTokens.Split.tertiaryText
    }

    private var splitMutedFill: Color {
        ColorTokens.Split.mutedFill
    }

    private var runningBackdrop: some View {
        LinearGradient(
            colors: [
                ColorTokens.Run.backdropStart,
                ColorTokens.Run.backdropEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var runningChrome: Color {
        ColorTokens.Run.chrome
    }

    private var runActionAccent: Color {
        RBColor.primary
    }

    private var runActionAccentGlow: Color {
        RBColor.secondary
    }

    private var runFinishTint: Color {
        Color(red: 0.49, green: 0.30, blue: 0.35)
    }

    private var displayPaceText: String {
        guard locationService.isPaceReliable,
              locationService.smoothedDisplayPaceSecondsPerKm > 0 else {
            return "--'--\""
        }
        return RunRecord.formatPace(locationService.smoothedDisplayPaceSecondsPerKm)
    }

    private var paceReadinessText: String {
        guard locationService.isPaceReliable else {
            return appLanguage.text("페이스 계산 중", "Calculating pace")
        }

        switch runSession.paceMaker.paceStatus {
        case .ahead:
            return appLanguage.text("조금 빠릅니다", "Slightly fast")
        case .onPace:
            return appLanguage.text("목표 페이스 유지", "On target")
        case .behind:
            return appLanguage.text("조금 느립니다", "Slightly slow")
        }
    }

    private var paceGuidanceTint: Color {
        guard locationService.isPaceReliable else { return RBColor.warning }
        return paceStatusColor
    }

    private var climateGuidanceState: RunClimateGuidanceState {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .hour], from: Date())
        let month = components.month ?? 1
        let hour = components.hour ?? 12
        let isWarmSeason = (6...9).contains(month)
        let isColdSeason = month == 12 || month <= 2
        let isMidday = (10...17).contains(hour)
        let isLowLightColdWindow = isColdSeason && (hour <= 7 || hour >= 19)

        if isWarmSeason && isMidday {
            return .highRisk
        }

        if isWarmSeason || isLowLightColdWindow {
            return .caution
        }

        return .stable
    }

    private var voiceGuideEnabled: Bool {
        UserDefaults.standard.bool(forKey: "voiceGuide")
    }

    private var paceStatusColor: Color {
        switch runSession.paceMaker.paceStatus {
        case .ahead:
            return RBColor.paceFast
        case .onPace:
            return RBColor.paceSteady
        case .behind:
            return RBColor.paceSlow
        }
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

    private func horizontalChromePadding(for width: CGFloat) -> CGFloat {
        width < LayoutTokens.compactViewportWidth
            ? ComponentTokens.RunSurface.verticalSpacingMedium
            : ComponentTokens.RunSurface.verticalSpacingLarge
    }

    private func viewportHeight(size: CGSize, safeAreaInsets: EdgeInsets) -> CGFloat {
        LayoutTokens.viewportHeight(size: size, safeAreaInsets: safeAreaInsets)
    }

    private func isCompactRunLayout(size: CGSize, safeAreaInsets: EdgeInsets) -> Bool {
        LayoutTokens.isCompactRunLayout(size: size, safeAreaInsets: safeAreaInsets)
    }

    private func runPageLayout(size: CGSize, safeAreaInsets: EdgeInsets) -> RunPageLayout {
        let compact = isCompactRunLayout(size: size, safeAreaInsets: safeAreaInsets)
        let horizontalPadding = LayoutTokens.runHorizontalPadding(compact: compact)
        let dockBottomPadding = ComponentTokens.RunActive.bottomOverlayBottom(safeBottom: safeAreaInsets.bottom)
        let buttonHeight = ComponentTokens.RunActive.runningControlHeight
        let musicBottomPadding = buttonHeight + dockBottomPadding + (compact ? 22 : 28)
        let musicSummaryTopPadding = max(size.height * (compact ? 0.18 : 0.20), compact ? 128 : 154)

        return RunPageLayout(
            width: size.width,
            height: size.height,
            contentWidth: max(size.width - (horizontalPadding * 2), 0),
            compact: compact,
            musicSummaryTopPadding: musicSummaryTopPadding,
            musicBottomPadding: musicBottomPadding,
            metricsTopPadding: compact ? 12 : 18,
            metricsBottomPadding: buttonHeight + dockBottomPadding + (compact ? 136 : 154),
            dockBottomPadding: dockBottomPadding
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = RunActiveViewportLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets,
                isPaused: runSession.runState == .paused
            )

            ZStack(alignment: .top) {
                runPageBackground(
                    compact: layout.compact,
                    size: geometry.size,
                    topInsetHeight: layout.pageTopPadding,
                    bottomInsetHeight: layout.pageBottomPadding
                )
                .ignoresSafeArea()

                pageContentLayer(layout: layout)
                .frame(width: layout.size.width, height: layout.size.height)
                .contentShape(Rectangle())
                .allowsHitTesting(!hasPreparedRunFinish && !isSavingRun)
                .zIndex(1)

                if !didFinish {
                    if hasPreparedRunFinish {
                        VStack {
                            Spacer(minLength: 0)
                            saveRetryPanel(contentWidth: layout.contentWidth)
                                .padding(.bottom, layout.bottomOverlayBottom)
                        }
                        .frame(width: layout.size.width, height: layout.size.height)
                        .zIndex(4)
                    } else {
                        VStack {
                            Spacer(minLength: 0)
                            fixedBottomLayer(
                                compact: layout.compact,
                                contentWidth: layout.contentWidth,
                                buttonHeight: ComponentTokens.RunActive.runningControlHeight,
                                pausedHeight: ComponentTokens.RunActive.pausedPanelHeight(compact: layout.compact)
                            )
                            .padding(.bottom, layout.bottomOverlayBottom)
                        }
                        .frame(width: layout.size.width, height: layout.size.height)
                        .zIndex(4)
                    }
                }

                if didFinish {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(5)
                }

                if isSavingRun {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                        .zIndex(5)

                    savingProgressOverlay
                        .frame(width: layout.size.width, height: layout.size.height)
                        .zIndex(6)
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDeviceConnection) {
            NavigationStack {
                DeviceConnectionView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
            guard runSession.runState == .running, !hasPreparedRunFinish else { return }
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
            guard runSession.runState == .running, !hasPreparedRunFinish else { return }

            if let location = locationService.currentLocation {
                runSession.healthKit.addRouteData([location])
            }
        }
        .onChange(of: locationService.smoothedDisplayPaceSecondsPerKm) { _, newPace in
            guard runSession.runState == .running,
                  !hasPreparedRunFinish,
                  locationService.isPaceReliable else { return }
            voiceGuide.handlePaceGuidanceUpdate(
                currentPaceSecondsPerKm: newPace,
                targetPaceSecondsPerKm: currentTargetPace.totalSecondsPerKm
            )
        }
        .onChange(of: runSession.paceMaker.gapMeters) { _, newGap in
            guard runSession.runState == .running, !hasPreparedRunFinish else { return }
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

    private func topOverlayHeight(compact: Bool) -> CGFloat {
        RunActiveLayoutHarness.topOverlayHeight(compact: compact)
    }

    private func bottomSurfaceHeight(compact: Bool, safeAreaBottom: CGFloat) -> CGFloat {
        let controlHeight = runSession.runState == .paused
            ? RunSurfaceToken.pausedPanelHeight(compact: compact)
            : RunSurfaceToken.runningControlHeight
        let summaryHeight: CGFloat = 0
        return controlHeight
            + summaryHeight
            + RunSurfaceToken.verticalSpacingLarge
            + max(safeAreaBottom, 8)
    }

    @ViewBuilder
    private func runPageBackground(compact: Bool, size: CGSize, topInsetHeight: CGFloat, bottomInsetHeight: CGFloat) -> some View {
        switch selectedPage {
        case .map:
            Color.black
                .ignoresSafeArea()
        case .audio:
            musicBackground
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
        case .control:
            controlBackground
        }
    }

    private func runTopOverlay(compact: Bool) -> some View {
        VStack(alignment: .center, spacing: RunSurfaceToken.verticalSpacingMedium) {
            RunModeToggle(
                titles: [
                    appLanguage.text("지도", "Map"),
                    appLanguage.text("오디오", "Audio"),
                    appLanguage.text("제어", "Control")
                ],
                selectedIndex: selectedPage.rawValue,
                onSelect: { index in
                    if let page = RunPage(rawValue: index) {
                        setSelectedPage(page)
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: RunSurfaceToken.modeToggleHeight + 8)

            RunMetricBar(items: runMetricBarItems, compact: compact)
                .frame(height: RunSurfaceToken.metricBarHeight(compact: compact))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func fixedTopLayer(
        contentWidth: CGFloat
    ) -> some View {
        RunPageIndicatorDots(pages: RunPage.allCases, selectedPage: selectedPage)
            .frame(width: contentWidth, height: ComponentTokens.RunActive.topIndicatorHeight)
    }

    @ViewBuilder
    private func fixedBottomLayer(
        compact: Bool,
        contentWidth: CGFloat,
        buttonHeight: CGFloat,
        pausedHeight: CGFloat
    ) -> some View {
        if !didFinish {
            RunBottomControl(
                isPaused: runSession.runState == .paused,
                contentWidth: contentWidth,
                runningHeight: buttonHeight,
                pausedHeight: pausedHeight
            ) {
                runPauseButton
            } pausedControl: {
                PausedBottomPanel(
                    message: appLanguage.text("러닝이 일시정지되었습니다", "Run paused"),
                    finishTitle: appLanguage.text("종료", "Finish"),
                    resumeTitle: appLanguage.text("계속 달리기", "Resume Run"),
                    onFinish: finishRun,
                    onResume: runSession.resumeRun,
                    compact: compact
                )
            }
        }
    }

    @ViewBuilder
    private func pageContentLayer(layout: RunActiveViewportLayout) -> some View {
        TabView(selection: $selectedPage) {
            mapTabContent(layout: layout)
                .tag(RunPage.map)

            audioPageContent(layout: layout)
                .tag(RunPage.audio)

            controlTabContent(layout: layout)
                .tag(RunPage.control)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeOut(duration: ComponentTokens.RunActive.pageAnimationDuration), value: selectedPage)
    }

    private func pacePageContent(layout: RunActiveViewportLayout) -> some View {
        RunPacePage(layout: layout) {
            currentPaceHeader(compact: layout.compact)
        } secondaryMetrics: {
            paceSecondaryMetrics(compact: layout.compact)
        } targetPanel: {
            targetPaceAdjustmentPanel(compact: layout.compact)
        } climateGuidance: {
            VStack(spacing: layout.compact ? ComponentTokens.RunSurface.verticalSpacingSmall : ComponentTokens.RunSurface.verticalSpacingMedium) {
                paceSensorStrip(compact: layout.compact)
                climateRiskGuidanceRow(compact: layout.compact)
            }
        }
    }

    private func currentPaceHeader(compact: Bool) -> some View {
        VStack(spacing: compact ? ComponentTokens.RunSurface.verticalSpacingMedium : ComponentTokens.RunSurface.verticalSpacingLarge) {
            HStack(spacing: ComponentTokens.RunSurface.verticalSpacingSmall) {
                Circle()
                    .fill(paceGuidanceTint)
                    .frame(width: 10, height: 10)

                Text(paceReadinessText)
                    .font(RBFont.label(compact ? 15 : 17))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            RBMetricLine(
                value: displayPaceText,
                unit: "/km",
                valueFont: RBFont.metric(TypographyTokens.currentPaceSize(compact: compact)),
                unitFont: RBFont.unit(TypographyTokens.unitSize(compact: compact, emphasis: .hero)),
                valueColor: .white,
                unitColor: Color.white.opacity(0.82),
                spacing: ComponentTokens.RunSurface.verticalSpacingSmall,
                alignment: .center
            )

            Text(appLanguage.text("현재 페이스", "Current pace"))
                .font(RBFont.caption(compact ? 12 : 13))
                .foregroundStyle(Color.white.opacity(0.56))
                .tracking(1.1)
        }
    }

    private func paceSecondaryMetrics(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 18 : 24) {
            paceSecondaryMetric(
                title: appLanguage.text("시간", "Time"),
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: "",
                valueSize: TypographyTokens.secondaryRunValueSize(compact: compact, kind: .time)
            )
            paceSecondaryMetric(
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                valueSize: TypographyTokens.secondaryRunValueSize(compact: compact, kind: .distance)
            )
        }
    }

    private func paceSecondaryMetric(title: String, value: String, unit: String, valueSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(RBFont.label(14))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(valueSize),
                unitFont: RBFont.unit(unit.isEmpty ? 1 : 17),
                valueColor: .white,
                unitColor: Color.white.opacity(0.76),
                spacing: 4,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func targetPaceAdjustmentPanel(compact: Bool) -> some View {
        let delta = targetPaceDeltaDisplay

        return VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(appLanguage.text("목표", "Target"))
                    .font(RBFont.label(14))
                    .foregroundStyle(Color.white.opacity(0.58))
                Text(currentTargetPace.formatted)
                    .font(RBFont.metric(compact ? 24 : 28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("/km")
                    .font(RBFont.unit(13))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }

            Text(delta.text)
                .font(RBFont.metric(compact ? 26 : 32))
                .foregroundStyle(delta.tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                paceTargetButton(title: "-10 sec", delta: -10)
                paceTargetButton(title: "-5 sec", delta: -5)
                paceTargetButton(title: "+5 sec", delta: 5)
                paceTargetButton(title: "+10 sec", delta: 10)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.26))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private func paceTargetButton(title: String, delta: Int) -> some View {
        Button {
            adjustTargetPace(by: delta)
        } label: {
            Text(title)
                .font(RBFont.label(13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var targetPaceDeltaDisplay: (text: String, tint: Color) {
        guard locationService.isPaceReliable,
              locationService.smoothedDisplayPaceSecondsPerKm > 0 else {
            return (appLanguage.text("페이스 계산 중", "Pace calculating"), RBColor.warning)
        }

        let deltaSeconds = Int((locationService.smoothedDisplayPaceSecondsPerKm - currentTargetPace.totalSecondsPerKm).rounded())
        let absDelta = abs(deltaSeconds)

        if absDelta <= 3 {
            return (appLanguage.text("목표 페이스", "On target"), RBColor.success)
        }

        if deltaSeconds > 0 {
            return (appLanguage.text("+\(absDelta)초 느림", "+\(absDelta) sec slow"), RBColor.paceSlow)
        }

        return (appLanguage.text("-\(absDelta)초 빠름", "-\(absDelta) sec fast"), RBColor.paceFast)
    }

    private func paceSensorStrip(compact: Bool) -> some View {
        HStack(spacing: 0) {
            paceSensorMetric(
                title: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint,
                compact: compact
            )

            paceSensorDivider

            paceSensorMetric(
                title: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor,
                compact: compact
            )

            paceSensorDivider

            paceSensorMetric(
                title: appLanguage.text("고도", "Elevation"),
                value: elevationText,
                unit: "m",
                tint: RBColor.primary,
                compact: compact
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 10 : 12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private var paceSensorDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 34)
    }

    private func paceSensorMetric(title: String, value: String, unit: String, tint: Color, compact: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(RBFont.caption(compact ? 11 : 12))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(compact ? 20 : 23),
                unitFont: RBFont.unit(compact ? 11 : 12),
                valueColor: tint,
                unitColor: Color.white.opacity(0.72),
                spacing: 3,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func climateRiskGuidanceRow(compact: Bool) -> some View {
        let state = climateGuidanceState

        if state != .stable {
            HStack(spacing: ComponentTokens.RunSurface.verticalSpacingMedium) {
                Image(systemName: "thermometer.sun")
                    .font(.system(size: compact ? 15 : 16, weight: .semibold))
                    .foregroundStyle(state.tint)
                    .frame(width: 32, height: 32)
                    .background(state.tint.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title(appLanguage))
                        .font(RBFont.label(compact ? 13 : 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(state.guidance(appLanguage))
                        .font(RBFont.caption(compact ? 11 : 12))
                        .foregroundStyle(Color.white.opacity(0.64))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, ComponentTokens.RunSurface.verticalSpacingMedium)
            .padding(.vertical, ComponentTokens.RunSurface.verticalSpacingSmall)
            .background(Color.black.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                    .stroke(state.tint.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
        }
    }

    private func audioAlertCard(compact: Bool) -> some View {
        HStack(spacing: ComponentTokens.RunSurface.verticalSpacingMedium) {
            Image(systemName: voiceGuideEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundStyle(voiceGuideEnabled ? RBColor.success : Color.white.opacity(0.58))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(voiceGuideEnabled ? appLanguage.text("음성 알림 대기", "Voice alerts armed") : appLanguage.text("음성 알림 꺼짐", "Voice alerts off"))
                    .font(RBFont.label(compact ? 14 : 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(appLanguage.text("페이스 이탈 · 30초 간격", "Pace drift · 30s cooldown"))
                    .font(RBFont.caption(compact ? 11 : 12))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 16 : 18)
        .padding(.vertical, compact ? 14 : 16)
        .background(RunSurfaceToken.darkPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous))
    }

    private func mapTabContent(layout: RunActiveViewportLayout) -> some View {
        ZStack {
            RunMapView(
                presentationMode: .routeOverview,
                showsRecenterButton: false,
                contentInsets: EdgeInsets(
                    top: layout.topOverlayTop + ComponentTokens.RunActive.topIndicatorHeight + 72,
                    leading: 0,
                    bottom: layout.pageBottomPadding,
                    trailing: 0
                ),
                interactionModes: []
            )
            .frame(width: layout.size.width, height: layout.size.height)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 8) {
                tabPageDots
                routeMapMetricsOverlay(compact: layout.compact)
                    .frame(width: layout.contentWidth)
                Spacer(minLength: 0)
            }
            .padding(.top, layout.topOverlayTop)
            .padding(.bottom, layout.pageBottomPadding)
            .frame(width: layout.size.width, height: layout.size.height)
            .allowsHitTesting(false)

            if locationService.routePoints.count < 2 {
                VStack {
                    Spacer(minLength: 0)
                    routeEmptyState(compact: layout.compact)
                        .frame(width: layout.contentWidth)
                    Spacer(minLength: 0)
                }
                .padding(.top, layout.pageTopPadding)
                .padding(.bottom, layout.pageBottomPadding)
                .frame(width: layout.size.width, height: layout.size.height)
                .allowsHitTesting(false)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func audioPageContent(layout: RunActiveViewportLayout) -> some View {
        let hudHeight: CGFloat = layout.compact ? 54 : 58
        let topReserve = layout.topOverlayTop
            + ComponentTokens.RunActive.topIndicatorHeight
            + 6
            + hudHeight
            + (layout.compact ? 10 : 14)
        let contentHeight = max(0, layout.size.height - topReserve - layout.pageBottomPadding)

        return ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: layout.compact ? 12 : 16) {
                    audioPaceDisplay(compact: layout.compact)
                        .frame(width: layout.contentWidth)

                    audioDistanceTimeDisplay(compact: layout.compact)
                        .frame(width: layout.contentWidth)

                    Spacer(minLength: layout.compact ? 8 : 14)

                    musicNowPlayingCard(compact: layout.compact)
                        .frame(width: layout.contentWidth)

                    musicControlRow(compact: layout.compact)
                        .frame(width: layout.contentWidth)

                    if shouldShowAudioAlertStatus {
                        audioAlertCard(compact: layout.compact)
                            .frame(width: layout.contentWidth)
                    }
                }
                .frame(minHeight: contentHeight)
                .padding(.top, topReserve)
                .padding(.bottom, layout.pageBottomPadding)
                .frame(width: layout.size.width)
            }

            VStack(spacing: 6) {
                tabPageDots
                audioMetricHUD(compact: layout.compact)
                    .frame(width: layout.contentWidth, height: hudHeight)
            }
            .padding(.top, layout.topOverlayTop)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .allowsHitTesting(false)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private var shouldShowAudioAlertStatus: Bool {
        runSession.coachingAlert != nil
    }

    private func controlTabContent(layout: RunActiveViewportLayout) -> some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: layout.compact ? 12 : 16) {
                    controlSummaryHeader(compact: layout.compact)
                        .frame(width: layout.contentWidth)

                    targetPaceCard
                        .frame(width: layout.contentWidth)

                    laserStatusSummaryCard
                        .frame(width: layout.contentWidth)

                    deviceIdentityCard
                        .frame(width: layout.contentWidth)

                    currentSplitCard
                        .frame(width: layout.contentWidth)
                }
                .padding(.top, layout.topOverlayTop + ComponentTokens.RunActive.topIndicatorHeight + 8)
                .padding(.bottom, layout.pageBottomPadding + ComponentTokens.RunSurface.verticalSpacingSmall)
                .frame(width: layout.size.width)
            }

            tabPageDots
                .padding(.top, layout.topOverlayTop)
                .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
                .allowsHitTesting(false)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private var tabPageDots: some View {
        RunPageIndicatorDots(pages: RunPage.allCases, selectedPage: selectedPage)
            .frame(height: ComponentTokens.RunActive.topIndicatorHeight)
    }

    private func audioMetricHUD(compact: Bool) -> some View {
        HStack(spacing: 0) {
            audioTopMetric(
                title: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint,
                compact: compact
            )

            topMetricDivider

            audioTopMetric(
                title: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor,
                compact: compact
            )

            topMetricDivider

            audioTopMetric(
                title: appLanguage.text("고도", "Altitude"),
                value: elevationText,
                unit: "m",
                tint: RBColor.primary,
                compact: compact
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.46))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private var topMetricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 30)
    }

    private func audioTopMetric(title: String, value: String, unit: String, tint: Color, compact: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(RBFont.caption(compact ? 10 : 11))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(compact ? 17 : 20),
                unitFont: RBFont.unit(compact ? 10 : 11),
                valueColor: tint,
                unitColor: Color.white.opacity(0.72),
                spacing: 3,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func audioPaceDisplay(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            Text(appLanguage.text("현재 페이스", "Current pace"))
                .font(RBFont.label(compact ? 13 : 14))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)

            RBMetricLine(
                value: displayPaceText,
                unit: "/km",
                valueFont: RBFont.metric(compact ? 66 : 76),
                unitFont: RBFont.unit(compact ? 18 : 20),
                valueColor: .white,
                unitColor: Color.white.opacity(0.82),
                spacing: 6,
                alignment: .center
            )

            HStack(spacing: 8) {
                Circle()
                    .fill(paceGuidanceTint)
                    .frame(width: 8, height: 8)

                Text(paceReadinessText)
                    .font(RBFont.caption(compact ? 12 : 13))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .shadow(color: Color.black.opacity(0.48), radius: 14, y: 7)
    }

    private func audioDistanceTimeDisplay(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 18 : 24) {
            audioSecondaryMetric(
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                valueSize: compact ? 34 : 42,
                unitSize: compact ? 14 : 16
            )

            audioSecondaryMetric(
                title: appLanguage.text("시간", "Time"),
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: "",
                valueSize: compact ? 38 : 48,
                unitSize: 1
            )
        }
    }

    private func audioSecondaryMetric(title: String, value: String, unit: String, valueSize: CGFloat, unitSize: CGFloat) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(RBFont.caption(12))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(valueSize),
                unitFont: RBFont.unit(unitSize),
                valueColor: .white,
                unitColor: Color.white.opacity(0.78),
                spacing: 4,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func controlSummaryHeader(compact: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appLanguage.text("BeamChaser 제어", "BeamChaser Control"))
                    .font(RBFont.title(compact ? 20 : 23))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(controlStatusText)
                    .font(RBFont.caption(compact ? 12 : 13))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)

            Text(currentTargetPace.formatted)
                .font(RBFont.metric(compact ? 24 : 28))
                .foregroundStyle(RBColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private var controlStatusText: String {
        if bleService.isConnected {
            return appLanguage.text("BeamChaser와 페이스를 동기화하고 있습니다", "Syncing pace with BeamChaser")
        }

        return appLanguage.text("목표 페이스를 바로 조절할 수 있습니다", "Adjust target pace instantly")
    }

    private var bleLatencyText: String {
        bleService.lastReceivedPacketHex == nil ? "--" : appLanguage.text("실시간", "Live")
    }

    private var runMetricBarItems: [RunMetricBarItem] {
        [
            RunMetricBarItem(
                title: appLanguage.text("페이스", "Pace"),
                value: displayPaceText,
                unit: "/km",
                tint: .white
            ),
            RunMetricBarItem(
                title: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint
            ),
            RunMetricBarItem(
                title: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor
            ),
            RunMetricBarItem(
                title: appLanguage.text("고도", "Elevation"),
                value: elevationText,
                unit: "m",
                tint: RBColor.primary
            )
        ]
    }

    @ViewBuilder
    private func runMainContent(compact: Bool, size: CGSize, topInsetHeight: CGFloat, bottomInsetHeight: CGFloat) -> some View {
        switch selectedPage {
        case .map:
            Color.clear
        case .audio:
            audioModeContent(compact: compact, topInsetHeight: topInsetHeight, bottomInsetHeight: bottomInsetHeight)
        case .control:
            laserModeContent(compact: compact, topInsetHeight: topInsetHeight, bottomInsetHeight: bottomInsetHeight)
        }
    }

    private func audioModeContent(compact: Bool, topInsetHeight: CGFloat, bottomInsetHeight: CGFloat) -> some View {
        let contentBottomPadding = bottomInsetHeight + (compact
            ? RunSurfaceToken.verticalSpacingSmall
            : RunSurfaceToken.verticalSpacingMedium)

        return VStack(spacing: 0) {
            RunPrimaryStats(
                distance: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                time: RunRecord.formatDuration(runSession.elapsedSeconds),
                pace: displayPaceText,
                compact: compact
            )
            .padding(.horizontal, RunSurfaceToken.horizontalPadding)
            .padding(.top, topInsetHeight + RunSurfaceToken.verticalSpacingMedium)

            Spacer(minLength: RunSurfaceToken.verticalSpacingLarge)

            VStack(spacing: compact ? 20 : 24) {
                musicNowPlayingCard(compact: compact)
                musicControlRow(compact: compact)
            }
            .padding(.horizontal, RunSurfaceToken.horizontalPadding)
            .padding(.bottom, contentBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func laserModeContent(compact: Bool, topInsetHeight: CGFloat, bottomInsetHeight: CGFloat) -> some View {
        let horizontalPadding = RunSurfaceToken.horizontalPadding + (compact ? 0 : 4)
        let contentBottomPadding = bottomInsetHeight + (compact
            ? RunSurfaceToken.verticalSpacingSmall
            : RunSurfaceToken.verticalSpacingMedium)

        return VStack(spacing: compact ? 12 : 14) {
            RunPrimaryStats(
                distance: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                time: RunRecord.formatDuration(runSession.elapsedSeconds),
                pace: displayPaceText,
                compact: true
            )

            targetPaceCard
            currentSplitCard
            deviceIdentityCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topInsetHeight + RunSurfaceToken.verticalSpacingSmall)
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var runPauseButton: some View {
        Button {
            runSession.pauseRun()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(appLanguage.text("러닝 일시정지", "Pause Run"))
                    .font(RBFont.label(16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: RunSurfaceToken.runningControlHeight)
            .background(RBColor.accentGradient)
            .overlay(
                RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var screenBackground: some View {
        runningBackdrop
            .ignoresSafeArea()
    }

    private var controlBackground: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.07, green: 0.08, blue: 0.10),
                Color(red: 0.03, green: 0.03, blue: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func selectedPageContent(_ layout: RunPageLayout) -> some View {
        switch selectedPage {
        case .map:
            mapPage(layout: layout)
        case .audio:
            musicPage(layout: layout)
        case .control:
            metricsPage(layout: layout)
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 34, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 48, abs(horizontal) > abs(vertical) * 1.15 else { return }

                if horizontal < 0, let next = selectedPage.next {
                    setSelectedPage(next)
                } else if horizontal > 0, let previous = selectedPage.previous {
                    setSelectedPage(previous)
                }
            }
    }

    private func setSelectedPage(_ page: RunPage) {
        withAnimation(.easeOut(duration: 0.16)) {
            selectedPage = page
        }
    }

    @ViewBuilder
    private var musicBackground: some View {
        if let artwork = nowPlayingService.artworkImage {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .saturation(0.85)
                .blur(radius: 28)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.78),
                            Color.black.opacity(0.72),
                            Color.black.opacity(0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.25),
                    Color(red: 0.05, green: 0.07, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var mapBackgroundLayer: some View {
        ZStack(alignment: .leading) {
            RunMapView(presentationMode: .routeOverview, showsRecenterButton: false)
                .ignoresSafeArea()

            Color.black.opacity(0.10)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea()
    }

    private func mapPage(layout: RunPageLayout) -> some View {
        RunMapPage(layout: layout) {
            ZStack {
                mapBackgroundLayer

                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    private var metricsBackground: some View {
        Color.black
            .ignoresSafeArea()
    }

    private func musicPage(layout: RunPageLayout) -> some View {
        RunMusicPage(
            layout: layout,
            background: { musicBackground },
            summary: { runSummaryBlock(compact: layout.compact) },
            card: { musicNowPlayingCard(compact: layout.compact) },
            controls: { musicControlRow(compact: layout.compact) }
        )
    }

    private func metricsPage(layout: RunPageLayout) -> some View {
        RunMetricsPage(layout: layout, background: { metricsBackground }) {
            runSummaryBlock(compact: true)
                .frame(width: layout.contentWidth)

            targetPaceCard
                .frame(width: layout.contentWidth)

            currentSplitCard
                .frame(width: layout.contentWidth)

            deviceIdentityCard
                .frame(width: layout.contentWidth)
        }
    }

    private var compactMapRunOverlay: some View {
        HStack(spacing: 0) {
            compactOverlayStat(
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km"
            )

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 34)

            compactOverlayStat(
                title: appLanguage.text("시간", "Time"),
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: ""
            )

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 34)

            compactOverlayStat(
                title: appLanguage.text("페이스", "Pace"),
                value: displayPaceText,
                unit: "/km"
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.52))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private func compactOverlayStat(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title.uppercased())
                .font(RBFont.caption(9))
                .foregroundStyle(Color.white.opacity(0.54))
                .tracking(0.7)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(16),
                unitFont: RBFont.unit(10),
                valueColor: .white,
                unitColor: Color.white.opacity(0.76),
                spacing: 3,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func musicNowPlayingCard(compact: Bool) -> some View {
        let artworkSize: CGFloat = compact ? 72 : 88
        let displayTitle = nowPlayingService.title.isEmpty
            ? appLanguage.text("재생 중인 음악 없음", "No Track Playing")
            : nowPlayingService.title
        let subtitle = nowPlayingService.artist.isEmpty
            ? (nowPlayingService.albumTitle.isEmpty
                ? appLanguage.text("시스템 오디오", "System Audio")
                : nowPlayingService.albumTitle)
            : nowPlayingService.artist

        return HStack(spacing: compact ? 12 : 14) {
            ZStack {
                if let artwork = nowPlayingService.artworkImage {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(RBFont.title(compact ? 26 : 30))
                            .foregroundStyle(Color.white.opacity(0.82))

                        Text(appLanguage.text("오디오", "Audio"))
                            .font(RBFont.caption(12))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }
            }
            .frame(width: artworkSize, height: artworkSize)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(RBFont.title(compact ? 18 : 20))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(RBFont.caption(compact ? 12 : 14))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: Color.black.opacity(0.34), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: RunSurfaceToken.audioCardHeight(compact: compact), alignment: .center)
        .padding(.horizontal, compact ? 18 : 20)
        .padding(.vertical, compact ? 18 : 20)
        .background(RunSurfaceToken.darkPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous))
    }

    private func musicControlRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 28 : 36) {
            musicTransportButton(
                systemName: "backward.fill",
                buttonSize: 56,
                iconSize: 22
            ) {
                nowPlayingService.skipToPreviousTrack()
            }

            musicTransportButton(
                systemName: nowPlayingService.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                buttonSize: 72,
                iconSize: 26
            ) {
                nowPlayingService.togglePlayback()
            }

            musicTransportButton(
                systemName: "forward.fill",
                buttonSize: 56,
                iconSize: 22
            ) {
                nowPlayingService.skipToNextTrack()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func routeMapMetricsOverlay(compact: Bool) -> some View {
        HStack(spacing: 0) {
            routeOverlayMetric(
                title: appLanguage.text("페이스", "Pace"),
                value: displayPaceText,
                unit: "/km",
                valueSize: compact ? 18 : 20
            )

            routeOverlayDivider

            routeOverlayMetric(
                title: appLanguage.text("시간", "Time"),
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: "",
                valueSize: compact ? 18 : 20
            )

            routeOverlayDivider

            routeOverlayMetric(
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                valueSize: compact ? 18 : 20
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private var routeOverlayDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 34)
    }

    private func routeOverlayMetric(title: String, value: String, unit: String, valueSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(RBFont.caption(10))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(valueSize),
                unitFont: RBFont.unit(unit.isEmpty ? 1 : 11),
                valueColor: .white,
                unitColor: Color.white.opacity(0.78),
                spacing: 3,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func routeEmptyState(compact: Bool) -> some View {
        Text(appLanguage.text("움직이기 시작하면 경로가 표시됩니다.", "Route will appear after movement starts."))
            .font(RBFont.label(compact ? 15 : 16))
            .foregroundStyle(.white.opacity(0.86))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private var laserStatusSummaryCard: some View {
        let isActive = bleService.deviceStatus?.isLaserActive == true
        let statusText = isActive
            ? appLanguage.text("레이저 신호 전송 중", "Laser signal active")
            : appLanguage.text("레이저 대기", "Laser standby")
        let batteryText = bleService.deviceStatus.map { "\($0.batteryPercent)%" } ?? "--"

        return splitCard(radius: RunSurfaceToken.cardRadius, contentPadding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(isActive ? RBColor.success : RBColor.warning)
                        .frame(width: 14, height: 14)
                        .shadow(color: (isActive ? RBColor.success : RBColor.warning).opacity(0.28), radius: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(RBFont.label(16))
                            .foregroundStyle(splitPrimaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(bleService.isConnected ? appLanguage.text("BeamChaser 연결됨", "BeamChaser connected") : appLanguage.text("BeamChaser 미연결", "BeamChaser disconnected"))
                            .font(RBFont.caption(12))
                            .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.warning)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: ComponentTokens.RunSurface.verticalSpacingSmall) {
                    hardwareStatusChip(title: appLanguage.text("배터리", "Battery"), value: batteryText)
                    hardwareStatusChip(title: appLanguage.text("존", "Zone"), value: bleService.deviceZone.label)
                    hardwareStatusChip(title: appLanguage.text("BLE 지연", "BLE"), value: bleLatencyText)
                }
            }
        }
    }

    private func runSummaryBlock(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            RunMetricLine(
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                valueSize: compact ? 72 : 84,
                unitSize: compact ? 19 : 22,
                valueColor: .white,
                unitColor: Color.white.opacity(0.80)
            )

            Text(RunRecord.formatDuration(runSession.elapsedSeconds))
                .font(.system(size: compact ? 36 : 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .center)

            RunMetricLine(
                value: displayPaceText,
                unit: "/km",
                valueSize: compact ? 30 : 36,
                unitSize: compact ? 13 : 16,
                valueColor: Color.white.opacity(0.90),
                unitColor: Color.white.opacity(0.72)
            )
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 166 : 196, alignment: .center)
        .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
    }

    private func topRunHUD(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 10) {
                pageIndicator

                Text(pageTitle(selectedPage))
                    .font(RBFont.caption(compact ? 13 : 14))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, compact ? 12 : 13)
                    .frame(height: compact ? 32 : 34)
                    .background(Color.black.opacity(0.76))
                    .overlay(
                        RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))

                Spacer(minLength: 0)
            }

            Group {
                if compact {
                    compactPaceIndicatorRow
                } else {
                    fullPaceIndicatorRow
                }
            }
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 10 : 12)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var fullPaceIndicatorRow: some View {
        HStack(alignment: .center, spacing: 18) {
            topBarStat(
                label: appLanguage.text("페이스", "Pace"),
                value: displayPaceText,
                unit: "/km",
                tint: .white
            )

            topBarStat(
                label: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint
            )

            topBarStat(
                label: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor,
                estimated: isCadenceEstimated
            )

            topBarStat(
                label: appLanguage.text("고도", "Elevation"),
                value: elevationText,
                unit: "m",
                tint: RBColor.accent
            )
        }
    }

    private var compactPaceIndicatorRow: some View {
        HStack(alignment: .center, spacing: 12) {
            topBarStat(
                label: appLanguage.text("페이스", "Pace"),
                value: displayPaceText,
                unit: "/km",
                tint: .white,
                compact: true
            )

            topBarStat(
                label: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint,
                compact: true
            )

            topBarStat(
                label: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor,
                compact: true,
                estimated: isCadenceEstimated
            )

            topBarStat(
                label: appLanguage.text("고도", "Elev"),
                value: elevationText,
                unit: "m",
                tint: RBColor.accent,
                compact: true
            )
        }
    }

    private func topBarStat(
        label: String,
        value: String,
        unit: String,
        tint: Color,
        compact: Bool = false,
        estimated: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(RBFont.caption(compact ? 10 : 11))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(RBFont.metric(compact ? 18 : 20))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if !unit.isEmpty {
                    Text(unit)
                        .font(RBFont.unit(compact ? 11 : 12))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if estimated, value != "--" {
                    Text("EST")
                        .font(RBFont.caption(compact ? 10 : 11))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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

    private var pageIndicator: some View {
        let activeColor = pageForegroundColor
        let inactiveColor = tertiaryForegroundColor

        return HStack(spacing: 8) {
            ForEach(RunPage.allCases) { page in
                Capsule()
                    .fill(selectedPage == page ? activeColor : inactiveColor)
                    .frame(width: selectedPage == page ? 20 : 7, height: 7)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.black.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))
        .allowsHitTesting(false)
    }

    private func pageTitle(_ page: RunPage) -> String {
        switch page {
        case .map:
            return appLanguage.text("지도", "Map")
        case .audio:
            return appLanguage.text("오디오", "Audio")
        case .control:
            return appLanguage.text("제어", "Control")
        }
    }

    private func controlDock(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 12) {
            if selectedPage == .map {
                compactMapRunOverlay
            }

            if runSession.runState == .paused {
                pausedControlDock(compact: compact)
            } else {
                runningControlDock(compact: compact)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func runningControlDock(compact: Bool) -> some View {
        wideControlButton(
            title: appLanguage.text("러닝 일시정지", "Pause Run"),
            icon: "pause.fill",
            fill: AnyShapeStyle(RBColor.accentGradient),
            height: compact ? 64 : 70
        ) {
            runSession.pauseRun()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private func paceAdjustmentRail(compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                paceAdjustmentButton(title: "-10", delta: -10)
                paceAdjustmentButton(title: "-5", delta: -5)
                paceAdjustmentButton(title: "+5", delta: 5)
                paceAdjustmentButton(title: "+10", delta: 10)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    paceAdjustmentButton(title: "-10", delta: -10)
                    paceAdjustmentButton(title: "-5", delta: -5)
                }
                HStack(spacing: 8) {
                    paceAdjustmentButton(title: "+5", delta: 5)
                    paceAdjustmentButton(title: "+10", delta: 10)
                }
            }
        }
        .padding(.horizontal, compact ? 0 : 2)
        .frame(maxWidth: .infinity)
    }

    private func paceAdjustmentButton(title: String, delta: Int) -> some View {
        Button {
            adjustTargetPace(by: delta)
        } label: {
            Text(title)
                .font(RBFont.label(14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pausedControlDock(compact: Bool) -> some View {
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
                    .frame(height: compact ? 52 : 56)
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
                    .frame(height: compact ? 52 : 56)
                    .background(RBColor.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.46))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
    }

    private func wideControlButton(
        title: String,
        icon: String,
        fill: AnyShapeStyle,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(RBFont.label(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func musicTransportButton(
        systemName: String,
        isPrimary: Bool = false,
        compact: Bool = false,
        buttonSize: CGFloat? = nil,
        iconSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedButtonSize: CGFloat = buttonSize ?? (isPrimary ? 84 : 56)
        let resolvedIconSize: CGFloat = iconSize ?? (isPrimary ? 30 : 22)

        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: resolvedIconSize, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.black.opacity(0.84) : .white)
                .frame(width: resolvedButtonSize, height: resolvedButtonSize)
                .background(
                    Circle()
                        .fill(isPrimary ? runActionAccent : Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isPrimary ? 0.12 : 0.16), lineWidth: 1)
                )
                .shadow(color: isPrimary ? runActionAccentGlow.opacity(0.24) : .clear, radius: 14, y: 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var targetPaceCard: some View {
        splitCard(radius: RunSurfaceToken.cardRadius, contentPadding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appLanguage.text("목표 페이스", "Target Pace"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(splitTertiaryText)
                        .tracking(0.8)

                    Spacer()

                    Text(currentTargetPace.formatted)
                        .font(RBFont.metric(28))
                        .foregroundStyle(RBColor.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        targetPaceAdjustButton(title: appLanguage.text("-10초", "-10s"), deltaSeconds: -10)
                        targetPaceAdjustButton(title: appLanguage.text("-5초", "-5s"), deltaSeconds: -5)
                        targetPaceAdjustButton(title: appLanguage.text("+5초", "+5s"), deltaSeconds: 5)
                        targetPaceAdjustButton(title: appLanguage.text("+10초", "+10s"), deltaSeconds: 10)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        targetPaceAdjustButton(title: appLanguage.text("-10초", "-10s"), deltaSeconds: -10)
                        targetPaceAdjustButton(title: appLanguage.text("-5초", "-5s"), deltaSeconds: -5)
                        targetPaceAdjustButton(title: appLanguage.text("+5초", "+5s"), deltaSeconds: 5)
                        targetPaceAdjustButton(title: appLanguage.text("+10초", "+10s"), deltaSeconds: 10)
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
                .font(RBFont.label(13))
                .foregroundStyle(splitPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(splitMutedFill)
                .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var currentSplitCard: some View {
        let snapshot = splitSnapshot.current
        let progress = min(max(snapshot.distanceMeters / 1000.0, 0), 1)

        return splitCard(radius: RunSurfaceToken.cardRadius, contentPadding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(appLanguage.text("현재 스플릿", "Current Split"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(splitTertiaryText)
                        .tracking(0.8)

                    Spacer()

                    Text(String(format: "%.2fkm", snapshot.distanceMeters / 1000.0))
                        .font(RBFont.metric(15))
                        .foregroundStyle(splitPrimaryText)
                }

                HStack(spacing: 12) {
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
                            .frame(height: 7)

                        Capsule()
                            .fill(RBColor.accent)
                            .frame(width: max(8, geo.size.width * progress), height: 7)
                    }
                }
                .frame(height: 7)
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
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if let delta {
                Text(formattedDelta(delta))
                    .font(RBFont.caption(11))
                    .foregroundStyle(delta <= 0 ? RBColor.success : RBColor.danger)
                    .lineLimit(1)
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
        splitCard(radius: RunSurfaceToken.cardRadius, contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(appLanguage.text("기기 연결", "Device"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(splitTertiaryText)
                        .tracking(0.8)

                    Spacer()

                    Text(bleService.isConnected ? appLanguage.text("연결됨", "Connected") : appLanguage.text("미연결", "Disconnected"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.warning)
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill(bleService.isConnected ? RBColor.success : RBColor.warning)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(bleService.connectedDeviceName ?? "BeamChaser")
                            .font(RBFont.label(13))
                            .foregroundStyle(splitPrimaryText)
                            .lineLimit(1)

                        Text(deviceIdentityStatusText)
                            .font(RBFont.caption(10))
                            .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.warning)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer()

                    Button {
                        showDeviceConnection = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(splitPrimaryText)
                            .frame(width: 36, height: 36)
                            .background(splitMutedFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                laserHardwareStatusChips
            }
        }
    }

    private var laserHardwareStatusChips: some View {
        let batteryText = bleService.deviceStatus.map { "\($0.batteryPercent)%" } ?? "--"
        let laserText = bleService.deviceStatus?.isLaserActive == true
            ? appLanguage.text("레이저 ON", "Laser ON")
            : appLanguage.text("레이저 대기", "Laser standby")
        let zoneText = bleService.deviceZone.label

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: ComponentTokens.RunSurface.verticalSpacingSmall) {
                hardwareStatusChip(title: appLanguage.text("배터리", "Battery"), value: batteryText)
                hardwareStatusChip(title: appLanguage.text("상태", "State"), value: laserText)
                hardwareStatusChip(title: appLanguage.text("존", "Zone"), value: zoneText)
            }

            VStack(spacing: ComponentTokens.RunSurface.verticalSpacingSmall) {
                HStack(spacing: ComponentTokens.RunSurface.verticalSpacingSmall) {
                    hardwareStatusChip(title: appLanguage.text("배터리", "Battery"), value: batteryText)
                    hardwareStatusChip(title: appLanguage.text("상태", "State"), value: laserText)
                }
                hardwareStatusChip(title: appLanguage.text("존", "Zone"), value: zoneText)
            }
        }
    }

    private func hardwareStatusChip(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(RBFont.caption(10))
                .foregroundStyle(splitTertiaryText)
                .lineLimit(1)
            Text(value)
                .font(RBFont.label(11))
                .foregroundStyle(splitPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(splitMutedFill)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))
    }

    private func runBottomSurface(compact: Bool, safeAreaBottom: CGFloat) -> some View {
        VStack(spacing: RunSurfaceToken.verticalSpacingMedium) {
            if selectedPage == .map {
                RunMapSummaryBar(items: mapSummaryItems, compact: compact)
                    .frame(height: RunSurfaceToken.runningControlHeight)
            }

            if runSession.runState == .paused {
                PausedBottomPanel(
                    message: appLanguage.text("러닝이 일시정지되었습니다", "Run paused"),
                    finishTitle: appLanguage.text("종료", "Finish"),
                    resumeTitle: appLanguage.text("계속 달리기", "Resume Run"),
                    onFinish: finishRun,
                    onResume: runSession.resumeRun,
                    compact: compact
                )
            } else {
                runPauseButton
            }
        }
        .padding(.horizontal, RunSurfaceToken.horizontalPadding)
        .padding(.top, RunSurfaceToken.verticalSpacingMedium)
        .padding(.bottom, max(8, safeAreaBottom == 0 ? 12 : 8))
        .background(Color.clear)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var mapSummaryItems: [RunMapSummaryBar.Item] {
        [
            RunMapSummaryBar.Item(
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km"
            ),
            RunMapSummaryBar.Item(
                title: appLanguage.text("시간", "Time"),
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: ""
            ),
            RunMapSummaryBar.Item(
                title: appLanguage.text("페이스", "Pace"),
                value: displayPaceText,
                unit: "/km"
            )
        ]
    }

#if false

    private var runPauseButton: some View {
        Button {
            runSession.pauseRun()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(appLanguage.text("러닝 일시정지", "Pause Run"))
                    .font(RBFont.label(16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: RunSurfaceToken.runningControlHeight)
            .background(RBColor.accentGradient)
            .overlay(
                RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var screenBackground: some View {
        runningBackdrop
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func selectedPageContent(_ layout: RunPageLayout) -> some View {
        switch selectedPage {
        case .map:
            mapPage(layout: layout)
        case .music:
            musicPage(layout: layout)
        case .metrics:
            metricsPage(layout: layout)
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 34, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 48, abs(horizontal) > abs(vertical) * 1.15 else { return }

                if horizontal < 0, let next = selectedPage.next {
                    setSelectedPage(next)
                } else if horizontal > 0, let previous = selectedPage.previous {
                    setSelectedPage(previous)
                }
            }
    }

    private func setSelectedPage(_ page: RunPage) {
        withAnimation(.easeOut(duration: 0.16)) {
            selectedPage = page
        }
    }

    @ViewBuilder
    private var musicBackground: some View {
        if let artwork = nowPlayingService.artworkImage {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .saturation(0.85)
                .blur(radius: 28)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.78),
                            Color.black.opacity(0.72),
                            Color.black.opacity(0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.25),
                    Color(red: 0.05, green: 0.07, blue: 0.11)
                ],
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
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                Color.black.opacity(0.10)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.48)
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

    private func mapPage(layout: RunPageLayout) -> some View {
        RunMapPage(layout: layout) {
            ZStack {
                mapBackgroundLayer

                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    private var metricsBackground: some View {
        Color.black
            .ignoresSafeArea()
    }

    private func musicPage(layout: RunPageLayout) -> some View {
        RunMusicPage(
            layout: layout,
            background: { musicBackground },
            summary: { runSummaryBlock(compact: layout.compact) },
            card: { musicNowPlayingCard(compact: layout.compact) },
            controls: { musicControlRow(compact: layout.compact) }
        )
    }

    private func metricsPage(layout: RunPageLayout) -> some View {
        RunMetricsPage(layout: layout, background: { metricsBackground }) {
            runSummaryBlock(compact: layout.compact)
                .frame(width: layout.contentWidth)

            targetPaceCard
                .frame(width: layout.contentWidth)

            currentSplitCard
                .frame(width: layout.contentWidth)

            splitsListCard
                .frame(width: layout.contentWidth)
        }
    }

    private var compactMapRunOverlay: some View {
        HStack(spacing: 0) {
            compactOverlayStat(
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km"
            )

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 34)

            compactOverlayStat(
                title: appLanguage.text("시간", "Time"),
                value: RunRecord.formatDuration(runSession.elapsedSeconds),
                unit: ""
            )

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 34)

            compactOverlayStat(
                title: appLanguage.text("페이스", "Pace"),
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km"
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.52))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private func compactOverlayStat(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title.uppercased())
                .font(RBFont.caption(9))
                .foregroundStyle(Color.white.opacity(0.54))
                .tracking(0.7)

            RBMetricLine(
                value: value,
                unit: unit,
                valueFont: RBFont.metric(16),
                unitFont: RBFont.unit(10),
                valueColor: .white,
                unitColor: Color.white.opacity(0.76),
                spacing: 3,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func musicNowPlayingCard(compact: Bool) -> some View {
        let artworkSize: CGFloat = compact ? 72 : 88
        let displayTitle = nowPlayingService.title.isEmpty
            ? appLanguage.text("재생 중인 음악 없음", "No Track Playing")
            : nowPlayingService.title
        let subtitle = nowPlayingService.artist.isEmpty
            ? (nowPlayingService.albumTitle.isEmpty
                ? appLanguage.text("시스템 오디오", "System Audio")
                : nowPlayingService.albumTitle)
            : nowPlayingService.artist

        return HStack(spacing: compact ? 12 : 14) {
            ZStack {
                if let artwork = nowPlayingService.artworkImage {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(RBFont.title(compact ? 26 : 30))
                            .foregroundStyle(Color.white.opacity(0.82))

                        Text(appLanguage.text("오디오", "Audio"))
                            .font(RBFont.caption(12))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }
            }
            .frame(width: artworkSize, height: artworkSize)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(RBFont.title(compact ? 18 : 20))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(RBFont.caption(compact ? 12 : 14))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: Color.black.opacity(0.34), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: RunSurfaceToken.audioCardHeight(compact: compact), alignment: .center)
        .padding(.horizontal, compact ? 18 : 20)
        .padding(.vertical, compact ? 18 : 20)
        .background(RunSurfaceToken.darkPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RunSurfaceToken.dividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous))
    }

    private func musicControlRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 28 : 36) {
            musicTransportButton(
                systemName: "backward.fill",
                buttonSize: 56,
                iconSize: 22
            ) {
                nowPlayingService.skipToPreviousTrack()
            }

            musicTransportButton(
                systemName: nowPlayingService.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                buttonSize: 84,
                iconSize: 30
            ) {
                nowPlayingService.togglePlayback()
            }

            musicTransportButton(
                systemName: "forward.fill",
                buttonSize: 56,
                iconSize: 22
            ) {
                nowPlayingService.skipToNextTrack()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func runSummaryBlock(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            RunMetricLine(
                value: String(format: "%.2f", locationService.totalDistanceMeters / 1000.0),
                unit: "km",
                valueSize: compact ? 72 : 84,
                unitSize: compact ? 19 : 22,
                valueColor: .white,
                unitColor: Color.white.opacity(0.80)
            )

            Text(RunRecord.formatDuration(runSession.elapsedSeconds))
                .font(.system(size: compact ? 36 : 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .center)

            RunMetricLine(
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km",
                valueSize: compact ? 30 : 36,
                unitSize: compact ? 13 : 16,
                valueColor: Color.white.opacity(0.90),
                unitColor: Color.white.opacity(0.72)
            )
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 166 : 196, alignment: .center)
        .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
    }

    private func topRunHUD(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 10) {
                pageIndicator

                Text(pageTitle(selectedPage))
                    .font(RBFont.caption(compact ? 13 : 14))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, compact ? 12 : 13)
                    .frame(height: compact ? 32 : 34)
                    .background(Color.black.opacity(0.76))
                    .overlay(
                        RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))

                Spacer(minLength: 0)
            }

            Group {
                if compact {
                    compactPaceIndicatorRow
                } else {
                    fullPaceIndicatorRow
                }
            }
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 10 : 12)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }


    private var fullPaceIndicatorRow: some View {
        HStack(alignment: .center, spacing: 18) {
            topBarStat(
                label: appLanguage.text("페이스", "Pace"),
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km",
                tint: .white
            )

            topBarStat(
                label: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint
            )

            topBarStat(
                label: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor,
                estimated: isCadenceEstimated
            )

            topBarStat(
                label: appLanguage.text("고도", "Elevation"),
                value: elevationText,
                unit: "m",
                tint: RBColor.accent
            )
        }
    }

    private var compactPaceIndicatorRow: some View {
        HStack(alignment: .center, spacing: 12) {
            topBarStat(
                label: appLanguage.text("페이스", "Pace"),
                value: RunRecord.formatPace(locationService.currentPaceSecondsPerKm),
                unit: "/km",
                tint: .white,
                compact: true
            )

            topBarStat(
                label: appLanguage.text("심박", "Heart"),
                value: heartRateText,
                unit: "bpm",
                tint: heartRateTint,
                compact: true
            )

            topBarStat(
                label: appLanguage.text("케이던스", "Cadence"),
                value: cadenceText,
                unit: "spm",
                tint: cadenceColor,
                compact: true,
                estimated: isCadenceEstimated
            )

            topBarStat(
                label: appLanguage.text("고도", "Elev"),
                value: elevationText,
                unit: "m",
                tint: RBColor.accent,
                compact: true
            )
        }
    }

    private func topBarStat(
        label: String,
        value: String,
        unit: String,
        tint: Color,
        compact: Bool = false,
        estimated: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(RBFont.caption(compact ? 10 : 11))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(RBFont.metric(compact ? 18 : 20))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if !unit.isEmpty {
                    Text(unit)
                        .font(RBFont.unit(compact ? 11 : 12))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if estimated, value != "--" {
                    Text("EST")
                        .font(RBFont.caption(compact ? 10 : 11))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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

    private var pageIndicator: some View {
        let activeColor = pageForegroundColor
        let inactiveColor = tertiaryForegroundColor

        return HStack(spacing: 8) {
            ForEach(RunPage.allCases) { page in
                Button {
                    setSelectedPage(page)
                } label: {
                    Capsule()
                        .fill(selectedPage == page ? activeColor : inactiveColor)
                        .frame(width: selectedPage == page ? 20 : 7, height: 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.black.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.chip, style: .continuous))
    }

    private func pageTitle(_ page: RunPage) -> String {
        switch page {
        case .map:
            return appLanguage.text("지도", "Map")
        case .music:
            return appLanguage.text("오디오", "Audio")
        case .metrics:
            return appLanguage.text("레이저", "Laser")
        }
    }

    private func controlDock(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 12) {
            if selectedPage == .map {
                compactMapRunOverlay
            }

            if runSession.runState == .paused {
                pausedControlDock(compact: compact)
            } else {
                runningControlDock(compact: compact)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func runningControlDock(compact: Bool) -> some View {
        wideControlButton(
            title: appLanguage.text("러닝 일시정지", "Pause Run"),
            icon: "pause.fill",
            fill: AnyShapeStyle(RBColor.accentGradient),
            height: compact ? 64 : 70
        ) {
            runSession.pauseRun()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private func paceAdjustmentRail(compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                paceAdjustmentButton(title: "-10", delta: -10)
                paceAdjustmentButton(title: "-5", delta: -5)
                paceAdjustmentButton(title: "+5", delta: 5)
                paceAdjustmentButton(title: "+10", delta: 10)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    paceAdjustmentButton(title: "-10", delta: -10)
                    paceAdjustmentButton(title: "-5", delta: -5)
                }
                HStack(spacing: 8) {
                    paceAdjustmentButton(title: "+5", delta: 5)
                    paceAdjustmentButton(title: "+10", delta: 10)
                }
            }
        }
        .padding(.horizontal, compact ? 0 : 2)
        .frame(maxWidth: .infinity)
    }

    private func paceAdjustmentButton(title: String, delta: Int) -> some View {
        Button {
            adjustTargetPace(by: delta)
        } label: {
            Text(title)
                .font(RBFont.label(14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pausedControlDock(compact: Bool) -> some View {
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
                    .frame(height: compact ? 52 : 56)
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
                    .frame(height: compact ? 52 : 56)
                    .background(RBColor.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.46))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
    }

    private func wideControlButton(
        title: String,
        icon: String,
        fill: AnyShapeStyle,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(RBFont.label(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func musicTransportButton(
        systemName: String,
        isPrimary: Bool = false,
        compact: Bool = false,
        buttonSize: CGFloat? = nil,
        iconSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedButtonSize: CGFloat = buttonSize ?? (isPrimary ? 84 : 56)
        let resolvedIconSize: CGFloat = iconSize ?? (isPrimary ? 30 : 22)

        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: resolvedIconSize, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.black.opacity(0.84) : .white)
                .frame(width: resolvedButtonSize, height: resolvedButtonSize)
                .background(
                    Circle()
                        .fill(isPrimary ? runActionAccent : Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isPrimary ? 0.12 : 0.16), lineWidth: 1)
                )
                .shadow(color: isPrimary ? runActionAccentGlow.opacity(0.24) : .clear, radius: 14, y: 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var targetPaceCard: some View {
        splitCard(radius: RunSurfaceToken.cardRadius, contentPadding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appLanguage.text("목표 페이스", "Target Pace"))
                        .font(RBFont.caption(12))
                        .foregroundStyle(splitTertiaryText)
                        .tracking(0.8)

                    Spacer()

                    Text(currentTargetPace.formatted)
                        .font(RBFont.metric(22))
                        .foregroundStyle(RBColor.primary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        targetPaceAdjustButton(title: appLanguage.text("-10초", "-10s"), deltaSeconds: -10)
                        targetPaceAdjustButton(title: appLanguage.text("-5초", "-5s"), deltaSeconds: -5)
                        targetPaceAdjustButton(title: appLanguage.text("+5초", "+5s"), deltaSeconds: 5)
                        targetPaceAdjustButton(title: appLanguage.text("+10초", "+10s"), deltaSeconds: 10)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        targetPaceAdjustButton(title: appLanguage.text("-10초", "-10s"), deltaSeconds: -10)
                        targetPaceAdjustButton(title: appLanguage.text("-5초", "-5s"), deltaSeconds: -5)
                        targetPaceAdjustButton(title: appLanguage.text("+5초", "+5s"), deltaSeconds: 5)
                        targetPaceAdjustButton(title: appLanguage.text("+10초", "+10s"), deltaSeconds: 10)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(presetTargetPaces, id: \.formatted) { target in
                        let isSelected = currentTargetPace.totalSecondsPerKm == target.totalSecondsPerKm

                        Button {
                            setTargetPace(target)
                        } label: {
                            Text(target.formatted)
                                .font(RBFont.label(14))
                                .foregroundStyle(isSelected ? RBColor.primary : splitPrimaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(isSelected ? RBColor.primary.opacity(0.18) : splitMutedFill)
                                .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(splitMutedFill)
                .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous))
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
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if let delta {
                Text(formattedDelta(delta))
                    .font(RBFont.caption(11))
                    .foregroundStyle(delta <= 0 ? RBColor.success : RBColor.danger)
                    .lineLimit(1)
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
                        .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.warning)
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(bleService.isConnected ? RBColor.success : RBColor.warning)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(bleService.connectedDeviceName ?? "BeamChaser")
                            .font(RBFont.label(14))
                            .foregroundStyle(splitPrimaryText)
                            .lineLimit(1)

                        Text(deviceIdentityStatusText)
                            .font(RBFont.caption(11))
                            .foregroundStyle(bleService.isConnected ? splitSecondaryText : RBColor.warning)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
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

#endif

    private var deviceIdentityStatusText: String {
        if let status = bleService.deviceStatus {
            return appLanguage.text("배터리 \(status.batteryPercent)%", "Battery \(status.batteryPercent)%")
        }

        return bleService.isConnected
            ? appLanguage.text("상태 정보를 확인하세요", "Check device status")
            : appLanguage.text("연결하면 페이스 신호를 전송합니다", "Connect to send pace signals")
    }

    private func splitCard<Content: View>(
        radius: CGFloat = RunSurfaceToken.controlRadius,
        contentPadding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(contentPadding)
            .background(splitCardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(splitCardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        .lineLimit(1)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
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

    private var currentCadenceSpm: Double {
        locationService.currentCadenceSpm
    }

    private var isCadenceEstimated: Bool {
        locationService.isCadenceEstimated
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

    private var estimatedHeartRateBpm: Int? {
        estimateHeartRate(
            paceSecondsPerKm: locationService.smoothedDisplayPaceSecondsPerKm,
            cadenceSpm: currentCadenceSpm
        )
    }

    private var isHeartRateEstimated: Bool {
        healthKit.isWorkoutActive && !healthKit.hasLiveHeartRate && estimatedHeartRateBpm != nil
    }

    private var heartRateTint: Color {
        healthKit.hasLiveHeartRate ? RBColor.accent : Color.white.opacity(0.92)
    }

    private var heartRateText: String {
        guard healthKit.isWorkoutActive else { return "--" }

        if healthKit.hasLiveHeartRate, healthKit.currentHeartRate > 0 {
            return String(Int(healthKit.currentHeartRate.rounded()))
        }

        if let estimatedHeartRateBpm {
            return String(estimatedHeartRateBpm)
        }

        return "--"
    }

    private var elevationText: String {
        let gain = Int(currentElevationGainMeters.rounded())
        return gain > 0 ? "+\(gain)" : "0"
    }

    private func estimateHeartRate(paceSecondsPerKm: Double, cadenceSpm: Double) -> Int? {
        let speedKmh = paceSecondsPerKm > 0 && paceSecondsPerKm.isFinite
            ? 3600.0 / paceSecondsPerKm
            : 0

        guard speedKmh > 0 || cadenceSpm > 0 else { return nil }

        let normalizedSpeed = min(max((speedKmh - 6.0) / 8.0, 0), 1)
        let normalizedCadence = min(max((cadenceSpm - 145.0) / 40.0, 0), 1)
        let estimate = 96.0 + (normalizedSpeed * 54.0) + (normalizedCadence * 24.0)

        return Int(min(max(estimate, 96.0), 188.0).rounded())
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
        return appLanguage.text("\(prefix)\(delta)초", "\(prefix)\(delta)s")
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
        guard !didFinish, !isSavingRun else { return }
        isSavingRun = true
        runSaveErrorMessage = nil

        if !hasPreparedRunFinish {
            hasPreparedRunFinish = true
            voiceGuide.announceRunFinish()
            locationService.simulatorStop()
        }

        let routePoints = locationService.routePoints
        let totalDistance = locationService.totalDistanceMeters
        let averageCadenceSpm = runSession.elapsedSeconds > 0
            ? Int((Double(locationService.sessionStepCount) / runSession.elapsedSeconds * 60.0).rounded())
            : nil
        let averageHeartRateBpm = runSession.healthKit.averageHeartRate > 0
            ? Int(runSession.healthKit.averageHeartRate.rounded())
            : nil

        do {
            let record = try runSession.finishRun(
                routePoints: routePoints,
                totalDistance: totalDistance,
                averageCadenceSpm: averageCadenceSpm,
                averageHeartRateBpm: averageHeartRateBpm
            )

            locationService.stopTracking()
            locationService.reset()
            voiceGuide.reset()
            isSavingRun = false
            didFinish = true
            appNavigation.openRunDetailAfterFinish(recordId: record.id)
        } catch {
            locationService.stopTracking()
            locationService.reset()
            voiceGuide.reset()
            isSavingRun = false
            runSaveErrorMessage = appLanguage.text(
                "러닝 기록을 저장하지 못했어요. 다시 시도해주세요.",
                "Couldn't save the run. Please try again."
            )
        }
    }

    private var savingProgressOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)

            Text(appLanguage.text("러닝 기록을 저장하는 중...", "Saving run..."))
                .font(RBFont.label(15))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveRetryPanel(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(runSaveErrorMessage ?? appLanguage.text("러닝 기록을 저장하지 못했어요. 다시 시도해주세요.", "Couldn't save the run. Please try again."))
                .font(RBFont.body(14))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            RBPrimaryButton(appLanguage.text("다시 시도", "Retry"), icon: "arrow.clockwise") {
                finishRun()
            }
        }
        .padding(18)
        .frame(width: contentWidth, alignment: .leading)
        .background(Color.black.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
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
