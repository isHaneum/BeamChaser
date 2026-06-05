import XCTest
import Combine
@testable import BeamChaser

@MainActor
final class SessionSyncTests: XCTestCase {
    
    var runSession: RunSessionManager!
    var mockBLE: MockBLEService!
    
    override func setUp() {
        super.setUp()
        mockBLE = MockBLEService()
        runSession = RunSessionManager()
        runSession.bleService = mockBLE
        runSession.clearAllSavedRecords()
    }

    override func tearDown() {
        runSession?.clearAllSavedRecords()
        runSession = nil
        mockBLE = nil
        super.tearDown()
    }
    
    func testStartRunSyncsWithBLE() {
        // Given
        let target = PaceTarget(minutesPerKm: 5, secondsPerKm: 30)
        
        // When
        runSession.startRun(target: target)
        
        // Then: MockBLEService에서 isRunning이 true가 되어야 함 (startRun 시뮬레이션)
        // 실제 MockBLEService는 startScanning 이후에 isConnected가 됨을 주의
        XCTAssertTrue(mockBLE.isConnected == false) // 초기 상태
        
        // 명시적으로 연결된 상태로 가정 (테스트를 위해)
        mockBLE.isConnected = true
        runSession.startRun(target: target)
        
        // Then
        XCTAssertEqual(runSession.runState, .running)
    }
    
    func testPaceStatusChangeTriggersBLEZone() {
        // Given: 연결된 상태
        mockBLE.isConnected = true
        let target = PaceTarget(minutesPerKm: 6, secondsPerKm: 0)
        runSession.startRun(target: target)
        
        // When: 훨씬 빠른 페이스로 업데이트 -> ahead 상태 유발
        runSession.updatePace(distance: 500) // 0초 시점에서 500m는 무조건 앞서감
        
        // Then: Zone이 Blue(빠름)으로 전송되어야 함
        XCTAssertEqual(mockBLE.deviceZone, .blue)
        
        // When: 훨씬 느린 페이스로 업데이트
        // 실제로는 elapsedSeconds가 증가해야 함을 시뮬레이션
        // RunSessionManager 내부 타이머가 아닌 수동 업데이트가 가능한지 확인 필요
        // 현재 updatePace는 elapsedSeconds를 사용함
    }

    func testRunRecordPersistsLocallyWithoutSignIn() {
        let target = PaceTarget(minutesPerKm: 5, secondsPerKm: 30)

        runSession.startRun(target: target)
        runSession.finishRun(routePoints: [], totalDistance: 120)

        XCTAssertEqual(runSession.savedRecords.count, 1)
        XCTAssertEqual(runSession.savedRecords.first?.totalDistanceMeters, 120)

        let reloadedSession = RunSessionManager()
        defer { reloadedSession.clearAllSavedRecords() }

        XCTAssertEqual(reloadedSession.savedRecords.count, 1)
        XCTAssertEqual(reloadedSession.savedRecords.first?.totalDistanceMeters, 120)
    }
}

final class RunMetricsAnalyzerTests: XCTestCase {
    func testFlatRunKeepsElevationGainNearZero() {
        let record = makeRecord(
            distanceMeters: 1_000,
            elapsedSeconds: 420,
            routePoints: stride(from: 0, through: 40, by: 1).map { index in
                makePoint(
                    metersEast: Double(index) * 25,
                    timestampOffset: Double(index) * 10,
                    altitude: 12 + [0.4, -0.3, 0.2, -0.5, 0.1][index % 5],
                    speed: 2.4,
                    horizontalAccuracy: 6,
                    verticalAccuracy: 5
                )
            }
        )

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertNotNil(analysis.elevationGainMeters)
        XCTAssertLessThanOrEqual(analysis.elevationGainMeters ?? .infinity, 5)
    }

    func testShortRunMarksDerivedMetricsUnavailable() {
        let record = makeRecord(
            distanceMeters: 80,
            elapsedSeconds: 32,
            cadence: 168,
            routePoints: [
                makePoint(metersEast: 0, timestampOffset: 0, altitude: 10, speed: 2.5, horizontalAccuracy: 5, verticalAccuracy: 4),
                makePoint(metersEast: 40, timestampOffset: 16, altitude: 11, speed: 2.5, horizontalAccuracy: 5, verticalAccuracy: 4),
                makePoint(metersEast: 80, timestampOffset: 32, altitude: 10.8, speed: 2.5, horizontalAccuracy: 5, verticalAccuracy: 4),
            ]
        )

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertNil(analysis.maxSpeedKmh)
        XCTAssertNil(analysis.elevationGainMeters)
        XCTAssertFalse(analysis.dataQuality.hasReliableCadence)
    }

    func testMissingHeartRateDoesNotBecomeReliable() {
        let record = makeRecord(distanceMeters: 1_000, elapsedSeconds: 400, routePoints: qualityRoute())

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertEqual(analysis.dataQuality.heartRateSource, .none)
        XCTAssertFalse(analysis.dataQuality.hasReliableHeartRate)
    }

    func testMissingCadenceDoesNotBecomeReliable() {
        let record = makeRecord(distanceMeters: 1_000, elapsedSeconds: 400, routePoints: qualityRoute())

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertEqual(analysis.dataQuality.cadenceSource, .none)
        XCTAssertFalse(analysis.dataQuality.hasReliableCadence)
    }

    func testCaloriesAlwaysRemainEstimated() {
        let record = makeRecord(distanceMeters: 1_200, elapsedSeconds: 420, routePoints: qualityRoute())

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertGreaterThan(analysis.caloriesEstimatedKcal, 0)
        XCTAssertTrue(analysis.caloriesUseDefaultWeight)
    }

    func testPoorHorizontalAccuracyDropsSpeedAndElevationReliability() {
        let route = stride(from: 0, through: 20, by: 1).map { index in
            makePoint(
                metersEast: Double(index) * 20,
                timestampOffset: Double(index) * 8,
                altitude: 20 + Double(index % 2),
                speed: 2.5,
                horizontalAccuracy: 35,
                verticalAccuracy: 6
            )
        }
        let record = makeRecord(distanceMeters: 400, elapsedSeconds: 160, routePoints: route)

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertEqual(analysis.dataQuality.gpsQuality, .poor)
        XCTAssertNil(analysis.maxSpeedKmh)
        XCTAssertNil(analysis.elevationGainMeters)
    }

    func testPoorVerticalAccuracyDropsElevationGain() {
        let route = stride(from: 0, through: 30, by: 1).map { index in
            makePoint(
                metersEast: Double(index) * 20,
                timestampOffset: Double(index) * 8,
                altitude: 10 + Double(index) * 0.5,
                speed: 2.5,
                horizontalAccuracy: 6,
                verticalAccuracy: 18
            )
        }
        let record = makeRecord(distanceMeters: 600, elapsedSeconds: 240, routePoints: route)

        let analysis = RunMetricsAnalyzer.analyze(record: record)

        XCTAssertNil(analysis.elevationGainMeters)
        XCTAssertFalse(analysis.dataQuality.hasReliableElevation)
    }

    private func qualityRoute() -> [RoutePoint] {
        stride(from: 0, through: 25, by: 1).map { index in
            makePoint(
                metersEast: Double(index) * 24,
                timestampOffset: Double(index) * 8,
                altitude: 15 + [0.2, -0.2, 0.3, -0.1][index % 4],
                speed: 2.8,
                horizontalAccuracy: 6,
                verticalAccuracy: 5
            )
        }
    }

    private func makeRecord(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        cadence: Int? = nil,
        heartRate: Int? = nil,
        routePoints: [RoutePoint]
    ) -> RunRecord {
        RunRecord(
            id: UUID(),
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            routePoints: routePoints,
            totalDistanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            targetPace: nil,
            runGoal: nil,
            intervalProgram: nil,
            averageCadenceSpm: cadence,
            averageHeartRateBpm: heartRate
        )
    }

    private func makePoint(
        metersEast: Double,
        timestampOffset: TimeInterval,
        altitude: Double,
        speed: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double
    ) -> RoutePoint {
        let baseLatitude = 37.5665
        let baseLongitude = 126.9780
        let longitudeOffset = metersEast / (111_320.0 * cos(baseLatitude * .pi / 180.0))

        return RoutePoint(
            latitude: baseLatitude,
            longitude: baseLongitude + longitudeOffset,
            altitude: altitude,
            timestamp: Date(timeIntervalSinceReferenceDate: timestampOffset),
            speed: speed,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy
        )
    }
}

final class RunDetailMetricBuilderTests: XCTestCase {
    func testCaloriesCardAlwaysIncludesEstimateLabel() {
        let cards = RunDetailMetricBuilder.cards(for: makeRecord(), appLanguage: .korean)

        XCTAssertEqual(cards.first { $0.id == "calories" }?.title, "칼로리(추정)")
    }

    func testMissingHeartRateShowsUnavailableCard() {
        let cards = RunDetailMetricBuilder.cards(for: makeRecord(), appLanguage: .korean)
        let heartRateCard = cards.first { $0.id == "heartRateUnavailable" }

        XCTAssertNotNil(heartRateCard)
        XCTAssertEqual(heartRateCard?.value, "--")
        XCTAssertEqual(heartRateCard?.subtitle, "심박수 측정 안 됨")
    }

    func testUnreliableCadenceCardIsHidden() {
        let record = makeRecord(distanceMeters: 80, elapsedSeconds: 32, cadence: 170)
        let cards = RunDetailMetricBuilder.cards(for: record, appLanguage: .korean)

        XCTAssertNil(cards.first { $0.id == "cadence" })
    }

    private func makeRecord(
        distanceMeters: Double = 1_200,
        elapsedSeconds: TimeInterval = 420,
        cadence: Int? = nil
    ) -> RunRecord {
        RunRecord(
            id: UUID(),
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            routePoints: stride(from: 0, through: 20, by: 1).map { index in
                let baseLatitude = 37.5665
                let baseLongitude = 126.9780
                let longitudeOffset = (Double(index) * 25) / (111_320.0 * cos(baseLatitude * .pi / 180.0))
                return RoutePoint(
                    latitude: baseLatitude,
                    longitude: baseLongitude + longitudeOffset,
                    altitude: 18 + [0.2, -0.1, 0.3, -0.2][index % 4],
                    timestamp: Date(timeIntervalSinceReferenceDate: Double(index) * 10),
                    speed: 2.8,
                    horizontalAccuracy: 6,
                    verticalAccuracy: 5
                )
            },
            totalDistanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            targetPace: nil,
            runGoal: nil,
            intervalProgram: nil,
            averageCadenceSpm: cadence,
            averageHeartRateBpm: nil
        )
    }
}
