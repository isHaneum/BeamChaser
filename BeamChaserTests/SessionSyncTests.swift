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
