import XCTest

/// Drives the Debug build in the Simulator. Run with scripts/uitests/run.sh, which starts Metro, and
/// see "Testing in the Simulator" in AGENTS.md. Keep the helpers and broadly useful tests here; add
/// tests for a one-off check, then remove them before committing.
final class SpacetimeUITests: XCTestCase {
  let app = XCUIApplication()

  /// Where screenshots and notes go: run.sh passes TEST_RUNNER_SHOTS, which arrives here as SHOTS.
  var shotsDir: String { ProcessInfo.processInfo.environment["SHOTS"] ?? NSTemporaryDirectory() }

  override func setUp() {
    continueAfterFailure = false
    app.launch()
    // A Debug build loads its JavaScript from Metro; this tells the dev client which server to use,
    // and keeps its developer menu (shown on a fresh install) and floating Tools button out of the way.
    app.open(
      URL(
        string: "exp+spacetime://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081"
          + "&__expo_disable_onboarding=1&__expo_disable_auto_launch=1&__expo_disable_fab=1")!)
    XCTAssertTrue(
      app.tabBars.buttons["Time"].waitForExistence(timeout: 120), "the app didn't load from Metro")
  }

  /// If the test failed, saves what the screen looked like as failure.png and failure.txt.
  override func tearDown() {
    if (testRun?.totalFailureCount ?? 0) > 0 {
      shot("failure")
      tree("failure")
    }
  }

  // MARK: Helpers

  /// Saves a screenshot to `<SHOTS>/<name>.png`.
  func shot(_ name: String) {
    let data = XCUIScreen.main.screenshot().pngRepresentation
    try? data.write(to: URL(fileURLWithPath: shotsDir).appendingPathComponent("\(name).png"))
  }

  /// Saves text, such as element frames, to `<SHOTS>/<name>.txt`.
  func note(_ name: String, _ text: String) {
    try? text.write(toFile: "\(shotsDir)/\(name).txt", atomically: true, encoding: .utf8)
  }

  /// Saves the accessibility tree (every element's type, label, identifier, and frame) to
  /// `<SHOTS>/<name>.txt`. Use it to find out how to query an element.
  func tree(_ name: String = "tree") {
    note(name, app.debugDescription)
  }

  /// Opens today in the Time tab's day view. Month view days are labeled with JS's
  /// `Date.toDateString()`, such as "Tue Oct 27 2026".
  func openToday() {
    app.tabBars.buttons["Time"].tap()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE MMM dd yyyy"
    let today = app.buttons[formatter.string(from: Date())]
    XCTAssertTrue(today.waitForExistence(timeout: 10))
    today.tap()
    XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 10))
  }

  // MARK: Tests

  /// Opens both tabs and today's day view. Doubles as a check that the setup works.
  func testSmoke() {
    shot("space")
    openToday()
    shot("day")
    tree()
  }
}
