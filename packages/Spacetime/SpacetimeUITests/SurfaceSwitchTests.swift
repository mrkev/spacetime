import XCTest

/// Switching between the map and the calendar with each one's own button, in place of a tab bar.
/// Set `TEST_RUNNER_SHOTS` to a folder to save a screenshot of each step there.
final class SurfaceSwitchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testSwitchingSurfaces() throws {
        let app = XCUIApplication()
        app.launch()
        let toTime = app.buttons["Time"]
        XCTAssert(toTime.waitForExistence(timeout: 15))
        XCTAssert(app.buttons["Here"].exists)
        sleep(2)
        shot("1-space")

        toTime.tap()
        let toSpace = app.buttons["Space"]
        XCTAssert(toSpace.waitForExistence(timeout: 5))
        XCTAssert(app.buttons["Today"].isHittable)
        XCTAssert(app.buttons["Reminders"].firstMatch.isHittable)
        XCTAssertFalse(toTime.isHittable, "The map's button is still showing")
        sleep(1)
        shot("2-time")

        // Into a day, where the bottom bar stays.
        app.buttons["Today"].tap()
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        let month = app.buttons[formatter.string(from: Date())]
        if !app.buttons[today].waitForExistence(timeout: 3), month.exists { month.tap() }
        if app.buttons[today].waitForExistence(timeout: 5) { app.buttons[today].tap() }
        sleep(2)
        shot("3-day")
        XCTAssert(toSpace.isHittable)

        toSpace.tap()
        XCTAssert(toTime.waitForExistence(timeout: 5) && toTime.isHittable)
        XCTAssertFalse(toSpace.isHittable, "The calendar's button is still showing")
        sleep(1)
        shot("4-space-again")

        // The calendar is where it was left.
        toTime.tap()
        XCTAssert(app.buttons["Add"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
