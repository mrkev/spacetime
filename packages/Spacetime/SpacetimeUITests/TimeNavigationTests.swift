import XCTest

/// Going back and forth between the Time tab's screens. Screens pushed after going back used to crash
/// when UIKit asked their toolbars for accessibility labels (see `TimeTab`), which UI tests and
/// VoiceOver both do.
final class TimeNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testPushingScreensAfterGoingBack() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.buttons["Time"].waitForExistence(timeout: 15))
        app.buttons["Time"].tap()
        // Today, in the month view (wherever the Time tab was left).
        app.buttons["Today"].tap()
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        let month = app.buttons[formatter.string(from: Date())]
        if !app.buttons["Reminders"].firstMatch.waitForExistence(timeout: 3) {
            back(app)
        } else if month.waitForExistence(timeout: 2) {
            month.tap()
        }
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)
        XCTAssert(app.buttons[today].waitForExistence(timeout: 5), "No button for \(today)")

        app.buttons[today].tap()
        XCTAssert(app.buttons["Add"].firstMatch.waitForExistence(timeout: 5))
        back(app)
        app.buttons["Reminders"].firstMatch.tap()
        XCTAssert(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
        back(app)
        if app.buttons["Alarms"].firstMatch.waitForExistence(timeout: 2) {
            app.buttons["Alarms"].firstMatch.tap()
            XCTAssert(app.navigationBars["Alarms"].waitForExistence(timeout: 5))
            back(app)
        }
        app.buttons[today].tap()
        XCTAssert(app.buttons["Add"].firstMatch.waitForExistence(timeout: 5))
        back(app)
        back(app)
        XCTAssert(month.waitForExistence(timeout: 5))
        month.tap()
        XCTAssert(app.buttons[today].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
