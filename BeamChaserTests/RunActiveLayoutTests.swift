import XCTest
@testable import BeamChaser

final class RunActiveLayoutTests: XCTestCase {
    func testTopOverlayHeightUsesFixedPageIndicator() {
        let compactHeight = RunActiveLayoutHarness.topOverlayHeight(compact: true)
        let regularHeight = RunActiveLayoutHarness.topOverlayHeight(compact: false)

        XCTAssertEqual(compactHeight, RunActiveLayoutHarness.topIndicatorHeight)
        XCTAssertEqual(regularHeight, RunActiveLayoutHarness.topIndicatorHeight)
        XCTAssertEqual(compactHeight, 28)
        XCTAssertEqual(regularHeight, 28)
    }

    func testTopOverlayHeightDoesNotDoubleCountSafeAreaTop() {
        let height = RunActiveLayoutHarness.topOverlayHeight(compact: false)
        let accidentalSafeAreaHeight = height + 59

        XCTAssertNotEqual(height, accidentalSafeAreaHeight)
    }

    func testRunningBottomControlsUseFixedHeights() {
        XCTAssertEqual(RunSurfaceToken.runningControlHeight, 76)
        XCTAssertEqual(RunSurfaceToken.pausedPanelHeight(compact: true), 150)
        XCTAssertEqual(RunSurfaceToken.pausedPanelHeight(compact: false), 160)
    }
}
