import SwiftUI
import MapKit

struct RunMapView: View {
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var runSession: RunSessionManager

    #if targetEnvironment(simulator)
    @State private var cameraPosition: MapCameraPosition = .automatic
    #else
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    #endif

    var body: some View {
        Map(position: $cameraPosition) {
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

            // 러닝 경로 — 네온 그린 글로우
            if locationService.routePoints.count >= 2 {
                // 글로우 배경
                MapPolyline(coordinates: locationService.routePoints.map(\.coordinate))
                    .stroke(
                        Color(red: 0.0, green: 1.0, blue: 0.5).opacity(0.3),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                    )
                // 메인 경로 라인
                MapPolyline(coordinates: locationService.routePoints.map(\.coordinate))
                    .stroke(
                        Color(red: 0.0, green: 1.0, blue: 0.5),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }

            // 레이저(가상 주자) 위치
            if let laserPosition = estimatedLaserPosition {
                Annotation("", coordinate: laserPosition) {
                    LaserDot(size: 16, glowRadius: 12)
                }
            }

            // 시작점
            if let start = locationService.routePoints.first {
                Annotation("", coordinate: start.coordinate) {
                    Circle()
                        .fill(RBColor.success)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {}  // 오버레이와 충돌 방지 — 컨트롤 최소화
        #if targetEnvironment(simulator)
        .onAppear {
            let coord = locationService.simulatedCoordinate
            cameraPosition = .camera(MapCamera(
                centerCoordinate: coord,
                distance: 800,
                heading: 0,
                pitch: 0
            ))
        }
        .onChange(of: locationService.routePoints.count) { _, _ in
            if let loc = locationService.currentLocation {
                withAnimation(.easeInOut(duration: 0.3)) {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: loc.coordinate,
                        distance: 800,
                        heading: 0,
                        pitch: 0
                    ))
                }
            }
        }
        #endif
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
