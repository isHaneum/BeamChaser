import SwiftUI
import MapKit

struct RunMapView: View {
    enum PresentationMode {
        case follow
        case routeOverview
    }

    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var runSession: RunSessionManager

    let presentationMode: PresentationMode
    let showsRecenterButton: Bool
    let contentInsets: EdgeInsets
    let interactionModes: MapInteractionModes

    init(
        presentationMode: PresentationMode = .follow,
        showsRecenterButton: Bool = true,
        contentInsets: EdgeInsets = EdgeInsets(),
        interactionModes: MapInteractionModes = .all
    ) {
        self.presentationMode = presentationMode
        self.showsRecenterButton = showsRecenterButton
        self.contentInsets = contentInsets
        self.interactionModes = interactionModes
    }

    #if targetEnvironment(simulator)
    @State private var cameraPosition: MapCameraPosition = .automatic
    #else
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    #endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $cameraPosition, interactionModes: interactionModes) {
                // 사용자 현재 위치
                #if targetEnvironment(simulator)
                if let loc = locationService.currentLocation {
                    Annotation("", coordinate: loc.coordinate) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .blue.opacity(0.5), radius: 6)
                    }
                }
                #else
                UserAnnotation()
                #endif

                // 러닝 경로 — 오렌지 글로우
                if locationService.routePoints.count >= 2 {
                    MapPolyline(coordinates: locationService.routePoints.map(\.coordinate))
                        .stroke(
                            Color(red: 1.0, green: 0.58, blue: 0.12).opacity(0.30),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: locationService.routePoints.map(\.coordinate))
                        .stroke(
                            Color(red: 1.0, green: 0.73, blue: 0.32),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: locationService.routePoints.map(\.coordinate))
                        .stroke(
                            Color(red: 1.0, green: 0.42, blue: 0.18),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                        )
                }

                if let laserPosition = estimatedLaserPosition {
                    Annotation("", coordinate: laserPosition) {
                        LaserDot(size: 16, glowRadius: 12)
                    }
                }

                if let start = locationService.routePoints.first {
                    Annotation("", coordinate: start.coordinate) {
                        Circle()
                            .fill(RBColor.success)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                if let last = locationService.routePoints.last, locationService.routePoints.count >= 2 {
                    Annotation("", coordinate: last.coordinate) {
                        Circle()
                            .fill(RBColor.laserRed)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onAppear {
                updateCamera(
                    animated: false,
                    forceRouteFit: presentationMode == .routeOverview && locationService.routePoints.count >= 2
                )
            }
            .onReceive(locationService.$currentLocation) { _ in
                guard presentationMode == .follow else { return }
                updateCamera(animated: false)
            }
            .onReceive(locationService.$routePoints) { _ in
                guard presentationMode == .routeOverview else { return }
                updateCamera(animated: true, forceRouteFit: locationService.routePoints.count >= 2)
            }

            if showsRecenterButton {
                Button {
                    updateCamera(animated: true, forceRouteFit: locationService.routePoints.count >= 2)
                } label: {
                    Image(systemName: presentationMode == .routeOverview ? "map" : "location.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(RBColor.accent)
                        .frame(width: 46, height: 46)
                        .background(Color.black.opacity(0.82))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .padding(.top, max(16, contentInsets.top + 12))
                .padding(.trailing, 16)
            }
        }
    }

    private func updateCamera(animated: Bool = true, forceRouteFit: Bool = false) {
        if forceRouteFit, let region = routeRegion {
            if animated {
                withAnimation(.easeInOut(duration: 0.35)) {
                    cameraPosition = .region(region)
                }
            } else {
                cameraPosition = .region(region)
            }
            return
        }

        let fallbackCoordinate: CLLocationCoordinate2D
        #if targetEnvironment(simulator)
        fallbackCoordinate = locationService.simulatedCoordinate
        #else
        fallbackCoordinate = locationService.currentLocation?.coordinate
            ?? routeRegion?.center
            ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        #endif

        let headingDegrees: Double
        #if targetEnvironment(simulator)
        headingDegrees = locationService.simulatorHeading * 180.0 / .pi
        #else
        headingDegrees = locationService.currentLocation?.course ?? 0
        #endif

        let chromeMultiplier = 1 + min((contentInsets.top + contentInsets.bottom) / 520, 0.40)
        let distance = max(180, min(580, max(locationService.totalDistanceMeters * 0.45, 240) * chromeMultiplier))

        let camera = MapCamera(
            centerCoordinate: locationService.currentLocation?.coordinate ?? fallbackCoordinate,
            distance: distance,
            heading: headingDegrees >= 0 ? headingDegrees : 0,
            pitch: 42
        )

        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)
        }
    }

    private var routeRegion: MKCoordinateRegion? {
        let coordinates = locationService.routePoints.map(\.coordinate)
        guard !coordinates.isEmpty else { return nil }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLon = longitudes.min(),
            let maxLon = longitudes.max()
        else {
            return nil
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: ((minLat + maxLat) / 2) + latitudeBias,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: adjustedLatitudeDelta,
                longitudeDelta: adjustedLongitudeDelta
            )
        )
    }

    private var adjustedLatitudeDelta: CLLocationDegrees {
        let coordinates = locationService.routePoints.map(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max() else { return 0.0035 }

        let base = max((maxLat - minLat) * 1.7, 0.0035)
        let verticalCoverage = min((contentInsets.top + contentInsets.bottom) / 520, 0.65)
        return base * (1 + verticalCoverage * 0.65)
    }

    private var adjustedLongitudeDelta: CLLocationDegrees {
        let coordinates = locationService.routePoints.map(\.coordinate)
        let longitudes = coordinates.map(\.longitude)
        guard let minLon = longitudes.min(), let maxLon = longitudes.max() else { return 0.0035 }

        let base = max((maxLon - minLon) * 1.7, 0.0035)
        let verticalCoverage = min((contentInsets.top + contentInsets.bottom) / 520, 0.65)
        return base * (1 + verticalCoverage * 0.18)
    }

    private var latitudeBias: CLLocationDegrees {
        let totalInsets = max(contentInsets.top + contentInsets.bottom, 1)
        let direction = (contentInsets.bottom - contentInsets.top) / totalInsets
        return adjustedLatitudeDelta * direction * 0.12
    }

    /// 목표 페이스 기준 레이저의 추정 위치
    /// 레이저는 사용자의 이동 방향 앞쪽에 갭 거리만큼 투사
    private var estimatedLaserPosition: CLLocationCoordinate2D? {
        guard let userLoc = locationService.currentLocation else { return nil }
        let gap = abs(runSession.paceMaker.gapMeters)
        guard gap > 0.5 else { return nil }  // 너무 가까우면 표시 안 함

        // 레이저가 앞에 있으면 (사용자가 뒤처지면) 이동 방향 앞에 표시
        // 레이저가 뒤에 있으면 (사용자가 앞서면) 이동 방향 뒤에 표시
        let isLaserAhead = runSession.paceMaker.gapMeters < 0  // 음수 = 뒤처짐 = 레이저가 앞

        // 이동 방향 계산
        let heading: Double
        #if targetEnvironment(simulator)
        heading = locationService.simulatorHeading  // 라디안
        #else
        if userLoc.course >= 0 {
            heading = userLoc.course * .pi / 180.0  // degree → 라디안
        } else if locationService.routePoints.count >= 2 {
            let last = locationService.routePoints[locationService.routePoints.count - 1]
            let prev = locationService.routePoints[locationService.routePoints.count - 2]
            heading = atan2(last.longitude - prev.longitude, last.latitude - prev.latitude)
        } else {
            heading = 0
        }
        #endif

        let direction = isLaserAhead ? 1.0 : -1.0
        let distMeters = gap * direction

        // heading: 0=북, 양수=시계방향 (atan2(x,y) 기준)
        let dy = distMeters * cos(heading)  // 남북
        let dx = distMeters * sin(heading)  // 동서

        let latOffset = dy / 111_320.0
        let lonOffset = dx / (111_320.0 * cos(userLoc.coordinate.latitude * .pi / 180))

        return CLLocationCoordinate2D(
            latitude: userLoc.coordinate.latitude + latOffset,
            longitude: userLoc.coordinate.longitude + lonOffset
        )
    }
}

#Preview {
    RunMapView()
        .environmentObject(LocationService())
        .environmentObject(RunSessionManager())
}
