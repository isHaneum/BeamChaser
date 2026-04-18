import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var locationService: LocationService
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
    @State private var panelExpanded = true       // 패널 펼침/접힘
    @State private var dragOffset: CGFloat = 0    // 드래그 중 오프셋

    // 접힌 상태: 로고 + 핸들만 보임
    private let collapsedHeight: CGFloat = 80
    // 탭바 기준 높이 (safe area bottom은 geo에서 런타임에 더함)
    private let tabBarBaseHeight: CGFloat = 100
    @State private var navigateToRunSetup = false
    @State private var navigateToDeviceConnection = false

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
                        .padding(.bottom, tabBarBaseHeight + geo.safeAreaInsets.bottom)  // 탭바 + safe area 위에 위치
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
            }
            .navigationDestination(isPresented: $navigateToDeviceConnection) {
                DeviceConnectionView()
            }
            .onAppear {
                #if targetEnvironment(simulator)
                // 시뮬레이터에서는 GPS 요청 건너뜀
                #else
                locationService.requestPermission()
                locationService.requestCurrentLocation()
                zoomWhenReady()
                #endif
            }
            .onChange(of: locationService.currentLocation) { _, newLoc in
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
        }
    }

    // MARK: - 현위치 버튼

    private var myLocationButton: some View {
        Button {
            #if targetEnvironment(simulator)
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: locationService.simulatedCoordinate,
                    distance: 800
                ))
            }
            #else
            locationService.requestCurrentLocation()
            if let loc = locationService.currentLocation {
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: loc.coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    ))
                }
            } else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .userLocation(fallback: .automatic)
                }
            }
            #endif
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RBColor.accent)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
    }

    // MARK: - 하단 패널 (드래그 가능)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            dragHandle

            if panelExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: -5)
        .offset(y: dragOffset)
        .gesture(panelDragGesture)
    }

    // MARK: - 드래그 핸들

    private var dragHandle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            // 접힌 상태에서 로고 간략 표시
            if !panelExpanded {
                HStack {
                    Text("RUN BEAM")
                        .font(RBFont.hero(18))
                        .foregroundStyle(RBColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RBColor.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
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

    // MARK: - 펼친 콘텐츠

    private var expandedContent: some View {
        VStack(spacing: 14) {
            // 로고 + 장치
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RUN BEAM")
                        .font(RBFont.hero(24))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(appLanguage.text("라인 레이저 페이스메이커", "Line Laser Pacemaker"))
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                }
                Spacer()
                Button {
                    openDeviceConnection()
                } label: {
                    deviceChip
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            actionButtons
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 접힌 콘텐츠 (아무것도 없음 — 핸들에 로고 포함)

    private var collapsedContent: some View {
        EmptyView()
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
        .background(RBColor.cardBg)
        .clipShape(Capsule())
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
                .frame(height: 56)
                .background(RBColor.cardBg)
                .overlay(
                    Capsule()
                        .stroke(bleService.isConnected ? RBColor.success.opacity(0.35) : RBColor.accent.opacity(0.35), lineWidth: 1)
                )
                .clipShape(Capsule())
            }

            Button {
                navigateToRunSetup = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(bleService.isConnected
                         ? appLanguage.text("시작하기", "Start Run")
                         : appLanguage.text("바로 시작", "Quick Start"))
                        .font(RBFont.label(15))
                        .lineLimit(1)
                }
                .foregroundStyle(RBColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RBColor.accentGradient)
                .clipShape(Capsule())
            }
        }
    }

    private func openDeviceConnection() {
        if !bleService.isConnected && !bleService.isScanning {
            bleService.startScanning()
        }
        navigateToDeviceConnection = true
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
}

#Preview {
    HomeView()
        .environmentObject(BLEService())
        .environmentObject(LocationService())
        .environmentObject(RunSessionManager())
}
