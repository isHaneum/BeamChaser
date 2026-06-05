import XCTest
@testable import BeamChaser

@MainActor
final class PaceMakerTests: XCTestCase {
    
    var paceMaker: PaceMakerEngine!
    
    override func setUp() {
        super.setUp()
        paceMaker = PaceMakerEngine()
    }
    
    func testPaceStatusAhead() {
        // Given: 목표 페이스 6:00/km (360s/km -> 2.77 m/s)
        let target = PaceTarget(minutesPerKm: 6, secondsPerKm: 0)
        paceMaker.start(target: target)
        
        // When: 100초 동안 500m를 달림 (5.0 m/s -> 3:20/km 페이스, 훨씬 빠름)
        // 100초 동안 목표 거리: 277.7m
        // 갭: 500 - 277.7 = 222.3m (ahead)
        paceMaker.update(actualDistanceMeters: 500, elapsedSeconds: 100)
        
        // Then
        XCTAssertEqual(paceMaker.paceStatus, .ahead)
        XCTAssertGreaterThan(paceMaker.gapMeters, 10.0)
    }
    
    func testPaceStatusBehind() {
        // Given: 목표 6:00/km
        let target = PaceTarget(minutesPerKm: 6, secondsPerKm: 0)
        paceMaker.start(target: target)
        
        // When: 100초 동안 100m만 달림 (1.0 m/s -> 16:40/km 페이스, 훨씬 느림)
        paceMaker.update(actualDistanceMeters: 100, elapsedSeconds: 100)
        
        // Then
        XCTAssertEqual(paceMaker.paceStatus, .behind)
        XCTAssertLessThan(paceMaker.gapMeters, -10.0)
    }
    
    func testPaceStatusOnPace() {
        // Given: 목표 6:00/km
        let target = PaceTarget(minutesPerKm: 6, secondsPerKm: 0)
        paceMaker.start(target: target)
        
        // When: 100초 동안 278m 달림 (거의 목표치 277.7m)
        paceMaker.update(actualDistanceMeters: 278, elapsedSeconds: 100)
        
        // Then
        XCTAssertEqual(paceMaker.paceStatus, .onPace)
        XCTAssertLessThan(abs(paceMaker.gapMeters), 10.0)
    }
}
