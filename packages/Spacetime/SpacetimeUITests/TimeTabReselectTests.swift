import XCTest

/// Tapping the selected Time tab: the tab bar pops to the year view and scrolls it to the top, which is
/// ten years back, so the app scrolls on to this year (see `RootView.reselect`).
final class TimeTabReselectTests: XCTestCase {
    @MainActor
    func testReselectingTimeGoesToThisYear() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.buttons["Time"].waitForExistence(timeout: 15))
        app.buttons["Time"].tap()
        app.buttons["Time"].tap()
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        let thisMonth = app.buttons[formatter.string(from: Date())]
        XCTAssert(thisMonth.waitForExistence(timeout: 5))
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        // The status bar doesn't scroll it to the top either.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.02)).tap()
        sleep(2)
        let tenYearsBack = app.buttons[formatter.string(from: Calendar.current.date(byAdding: .year, value: -10, to: Date())!)]
        XCTAssertFalse(tenYearsBack.exists, "The status bar scrolled to the top")
        // Twice: the second time, the year view already thinks it's on this year.
        for _ in 0..<2 {
            app.buttons["Time"].tap()
            sleep(2)
            XCTAssert(thisMonth.exists && thisMonth.isHittable, "This year isn't showing")
        }
    }
}
