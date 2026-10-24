import XCTest

/// Scripted walkthrough that CI records for the App Store preview and the
/// social video. Each step prints "TOURMARK <name> <unix time>" so the editor
/// (tools/make_videos.py) can line captions up with the footage. Steps are
/// forgiving: a missing element skips that step instead of ending the tour.
final class TourUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-demo", "-ui-tab", "overview"]
        app.launch()
        _ = app.navigationBars["Billow"].waitForExistence(timeout: 20)
        pause(1.0)
        let window = app.windows.firstMatch

        mark("overview")
        pause(3.0)

        mark("scrub")
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.585))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.585))
        // Slow drag (points/second) so viewers can watch the highlighted day move.
        from.press(forDuration: 0.4, thenDragTo: to, withVelocity: XCUIGestureVelocity(180),
                   thenHoldForDuration: 1.0)
        pause(0.5)

        mark("scroll")
        window.swipeUp(velocity: .slow)
        pause(2.2)

        mark("activity")
        tapTab(app, "Activity")
        pause(1.4)
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            pause(0.4)
            search.typeText("mart")
            pause(1.0)
            let searchKey = app.keyboards.buttons["search"]
            if searchKey.exists { searchKey.tap() }
            pause(0.8)
        }

        mark("recategorize")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Everyday Mart")).firstMatch
        if row.waitForExistence(timeout: 5) { row.tap() }
        pause(1.3)
        let groceries = app.buttons["Groceries"].firstMatch
        if groceries.waitForExistence(timeout: 5) { groceries.tap() }
        pause(1.4)
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
        pause(1.0)

        mark("connect")
        tapTab(app, "Accounts")
        pause(1.2)
        let setup = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Set up bank sync")).firstMatch
        if setup.waitForExistence(timeout: 5) { setup.tap() }
        pause(3.0)
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        pause(0.6)

        mark("finale")
        tapTab(app, "Overview")
        pause(3.0)
        mark("end")
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ name: String) {
        print("TOURMARK \(name) \(String(format: "%.3f", Date().timeIntervalSince1970))")
    }
}
