import SwiftUI
import MapKit

struct HomeView: View {

    @Binding private var hidesRootTabBar: Bool
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject private var appNavigation: AppNavigationModel
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    #if targetEnvironment(simulator)
    @State private var cameraPosition: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        distance: 800
    ))
    @State private var isDefaultPosition = false
    #else
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .automatic
    )
    @State private var isDefaultPosition = true
    #endif
    @State private var panelExpanded = false      // 기본: 버튼만 / 펼침: 챌린지도 표시
    @State private var dragOffset: CGFloat = 0    // 드래그 중 오프셋

    // 접힌 상태: 버튼까지만
    private let collapsedHeight: CGFloat = 74
    @State private var navigateToRunSetup = false
    @State private var navigateToDeviceConnection = false

    init(hidesRootTabBar: Binding<Bool> = .constant(false)) {
        _hidesRootTabBar = hidesRootTabBar
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // ── 지도 ──
                    Map(position: $cameraPosition, interactionModes: .all) {
                        #if targetEnvironment(simulator)
                        Annotation("", coordinate: locationService.simulatedCoordinate) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(color: .blue.opacity(0.5), radius: 6)
                        }
                        #else
                        UserAnnotation()
                        #endif
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapScaleView()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)

                    // ── 하단 패널 ──
                    bottomPanel
                        .padding(.bottom, RBLayout.tabBarClearance + max(geo.safeAreaInsets.bottom, 10))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                myLocationButton
                    .padding(.trailing, 16)
                    .padding(.top, 60)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToRunSetup) {
                PaceSetupView()
                    .onAppear { hidesRootTabBar = true }
                    .onDisappear { updateRootTabVisibility() }
            }
            .navigationDestination(isPresented: $navigateToDeviceConnection) {
                DeviceConnectionView()
                    .onAppear { hidesRootTabBar = true }
                    .onDisappear { updateRootTabVisibility() }
            }
            .onChange(of: navigateToRunSetup) { _, _ in
                updateRootTabVisibility()
            }
            .onChange(of: navigateToDeviceConnection) { _, _ in
                updateRootTabVisibility()
            }
            .onChange(of: appNavigation.homeNavigationResetToken) { _, _ in
                navigateToRunSetup = false
                navigateToDeviceConnection = false
                updateRootTabVisibility()
            }
            .onAppear {
                updateRootTabVisibility()
                #if targetEnvironment(simulator)
                // 시뮬레이터에서는 GPS 요청 건너뜀
                #else
                locationService.requestPermission()
                locationService.requestCurrentLocation()
                zoomWhenReady()
                #endif
            }
            .onReceive(locationService.$currentLocation) { newLoc in
                if let loc = newLoc, isDefaultPosition {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: loc.coordinate,
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        ))
                    }
                    isDefaultPosition = false
                }
            }
        }
    }

    // MARK: - 위치 줌

    private func zoomWhenReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: {
            if let loc = locationService.currentLocation {
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: loc.coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    ))
                }
                isDefaultPosition = false
            }
        })
    }

    // MARK: - 현위치 버튼

    private var myLocationButton: some View {
        Button {
            #if targetEnvironment(simulator)
            let coordinate = locationService.simulatedCoordinate
            #else
            let coordinate = locationService.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
            #endif

            withAnimation(.easeInOut(duration: 0.55)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))
            }
            isDefaultPosition = false
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(RBColor.accent)
                .frame(width: 54, height: 54)
                .background(RBColor.chrome)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            dragHandle
            // 항상 버튼 표시
            buttonContent
            // 드래그업 시 챌린지 추가 표시
            if panelExpanded {
                challengeSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: collapsedHeight, alignment: .top)
        .background(RBColor.chrome)
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(RBColor.divider.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        .padding(.horizontal, 12)
        .offset(y: dragOffset)
        .gesture(panelDragGesture)
    }

    // MARK: - 드래그 핸들

    private var dragHandle: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(RBColor.textTertiary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                panelExpanded.toggle()
            }
        }
    }

    // MARK: - 드래그 제스처

    private var panelDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // 아래로 드래그하면 양수
                let translation = value.translation.height
                if panelExpanded {
                    dragOffset = max(0, translation)  // 아래로만
                } else {
                    dragOffset = min(0, translation)  // 위로만
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 60
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if panelExpanded && value.translation.height > threshold {
                        panelExpanded = false
                    } else if !panelExpanded && value.translation.height < -threshold {
                        panelExpanded = true
                    }
                    dragOffset = 0
                }
            }
    }

    // MARK: - 항상 표시: 로고 + 버튼

    private var buttonContent: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BeamChaser")
                        .font(RBFont.hero(24))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(appLanguage.text("라인 레이저 페이스메이커", "Line Laser Pacemaker"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textSecondary)
                }
                Spacer()
                Button {
                    openDeviceConnection()
                } label: {
                    deviceChip
                }
                .buttonStyle(.plain)

                // 챌린지 접힘/펼침 화살표
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        panelExpanded.toggle()
                    }
                } label: {
                    Image(systemName: panelExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RBColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    panelExpanded
                    ? appLanguage.text("챌린지 패널 접기", "Collapse challenges panel")
                    : appLanguage.text("챌린지 패널 펼치기", "Expand challenges panel")
                )
            }
            .padding(.horizontal, 20)

            actionButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
        .padding(.top, 6)
    }

    // MARK: - 장치 상태 칩

    private var deviceChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(bleService.isConnected ? RBColor.success : RBColor.danger)
                .frame(width: 8, height: 8)
            Text(bleService.isConnected ? appLanguage.text("연결됨", "Connected") : appLanguage.text("미연결", "Disconnected"))
                .font(RBFont.caption(11))
                .foregroundStyle(bleService.isConnected ? RBColor.textSecondary : RBColor.danger)
            if bleService.isConnected {
                if let status = bleService.deviceStatus {
                    Text("·")
                        .foregroundStyle(RBColor.textTertiary)
                    batteryIcon(percent: status.batteryPercent, isCharging: status.isCharging)
                        .font(.system(size: 12))
                    Text("\(status.batteryPercent)%")
                        .font(RBFont.metric(11))
                        .foregroundStyle(batteryColor(status.batteryPercent))
                    if status.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(RBColor.success)
                    }
                } else {
                    Text("·")
                        .foregroundStyle(RBColor.textTertiary)
                    Image(systemName: "battery.50percent")
                        .font(.system(size: 12))
                        .foregroundStyle(RBColor.textTertiary)
                    Text("--")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                openDeviceConnection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: bleService.isConnected ? "slider.horizontal.3" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                    Text(bleService.isConnected
                         ? appLanguage.text("장치 관리", "Manage Device")
                         : appLanguage.text("장치 연결", "Connect Device"))
                        .font(RBFont.label(15))
                        .lineLimit(1)
                }
                .foregroundStyle(RBColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RBColor.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                        .stroke(bleService.isConnected ? RBColor.success.opacity(0.35) : RBColor.accent.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
            }

            Button {
                navigateToRunSetup = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(RBColor.onAccent)
                    Text(bleService.isConnected
                         ? appLanguage.text("시작하기", "Start Run")
                         : appLanguage.text("바로 시작", "Quick Start"))
                        .font(RBFont.label(15))
                        .foregroundStyle(RBColor.onAccent)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RBColor.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
            }
        }
    }

    private func openDeviceConnection() {
        if !bleService.isConnected && !bleService.isScanning {
            bleService.startScanning()
        }
        navigateToDeviceConnection = true
        updateRootTabVisibility()
    }

    private func updateRootTabVisibility() {
        hidesRootTabBar = navigateToRunSetup || navigateToDeviceConnection
    }

    private func batteryIcon(percent: Int, isCharging: Bool) -> some View {
        let iconName: String
        if isCharging {
            iconName = "battery.100percent.bolt"
        } else if percent > 75 {
            iconName = "battery.100percent"
        } else if percent > 50 {
            iconName = "battery.75percent"
        } else if percent > 25 {
            iconName = "battery.50percent"
        } else {
            iconName = "battery.25percent"
        }
        return Image(systemName: iconName)
            .foregroundStyle(batteryColor(percent))
    }

    private func batteryColor(_ percent: Int) -> Color {
        if percent > 50 { return RBColor.success }
        if percent > 20 { return .yellow }
        return RBColor.danger
    }

    private var challengeSection: some View {
        let weekly = backendService.currentWeeklyChallenge
            ?? FirestoreChallengeProgress.weeklySnapshot(
                userId: backendService.userId ?? "local",
                records: runSession.savedRecords,
                monthlyGoal: profileService.monthlyGoal
            )
        let monthly = backendService.currentMonthlyChallenge
            ?? FirestoreChallengeProgress.monthlySnapshot(
                userId: backendService.userId ?? "local",
                records: runSession.savedRecords,
                monthlyGoal: profileService.monthlyGoal
            )

        return VStack(alignment: .leading, spacing: 12) {
            Text(appLanguage.text("챌린지", "Challenges"))
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)

            challengeCard(weekly, tint: RBColor.accent)
            challengeCard(monthly, tint: RBColor.success)
        }
    }

    private func challengeCard(_ challenge: FirestoreChallengeProgress, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(challenge.title(appLanguage))
                        .font(RBFont.label(15))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(challenge.periodLabel(appLanguage))
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textSecondary)
                }

                Spacer()

                Text("\(Int((challenge.combinedProgress * 100).rounded()))%")
                    .font(RBFont.metric(18))
                    .foregroundStyle(tint)
            }

            challengeProgressRow(
                label: appLanguage.text("러닝", "Runs"),
                currentText: "\(challenge.completedRunCount)",
                targetText: "\(challenge.targetRunCount)",
                progress: challenge.runProgress,
                tint: tint
            )

            challengeProgressRow(
                label: appLanguage.text("거리", "Distance"),
                currentText: String(format: "%.1fkm", challenge.completedDistanceKm),
                targetText: String(format: "%.1fkm", challenge.targetDistanceKm),
                progress: challenge.distanceProgress,
                tint: tint.opacity(0.8)
            )

            HStack(spacing: 8) {
                challengeStatChip(
                    icon: "figure.run",
                    text: appLanguage.text("레이저 \(challenge.pacedRunCount)회", "Laser \(challenge.pacedRunCount)")
                )
                challengeStatChip(
                    icon: "flag.checkered",
                    text: appLanguage.text("목표 달성 \(challenge.goalHitCount)회", "Goal Hit \(challenge.goalHitCount)")
                )
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func challengeProgressRow(
        label: String,
        currentText: String,
        targetText: String,
        progress: Double,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
                Spacer()
                Text(currentText)
                    .font(RBFont.metric(12))
                    .foregroundStyle(RBColor.textPrimary)
                Text("/")
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textTertiary)
                Text(targetText)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(RBColor.cardBgLight)
                        .frame(height: 8)

                    Capsule()
                        .fill(tint)
                        .frame(width: max(10, geo.size.width * min(1.0, progress)), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private func challengeStatChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(RBFont.caption(11))
        }
        .foregroundStyle(RBColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
    }
}

#Preview {
    HomeView()
        .environmentObject(BLEService())
        .environmentObject(LocationService())
        .environmentObject(RunSessionManager())
        .environmentObject(ProfileService())
        .environmentObject(BackendService())
}
