import XCTest

// OWNER: wt/controls-ui. Simulator hit-testing harness for the control
// surface. The host CameraCore tests cannot catch overlay/touch regressions
// (e.g. effect views swallowing button taps), so this drives the real app.
final class ControlsPanelUITests: XCTestCase {
    @MainActor
    func testSettingsToggleOpensAndClosesDrawer() {
        let app = XCUIApplication()
        app.launch()

        let show = app.buttons["Show settings"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), "settings toggle not found")
        show.tap()

        let drawerLabel = app.staticTexts["EXPOSURE"]
        XCTAssertTrue(
            drawerLabel.waitForExistence(timeout: 5),
            "drawer did not open after tapping the settings toggle")

        // Controls inside the drawer must also receive taps on the glass
        // surface: switch EXPOSURE to manual and expect the ISO slider label.
        let manual = app.buttons["M"].firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 2), "exposure A/M segment not found")
        manual.tap()
        XCTAssertTrue(
            app.staticTexts["ISO"].waitForExistence(timeout: 3),
            "manual exposure controls did not appear after tapping M")

        let hide = app.buttons["Hide settings"]
        XCTAssertTrue(hide.waitForExistence(timeout: 2), "toggle did not flip to hide state")
        hide.tap()

        XCTAssertTrue(
            drawerLabel.waitForNonExistence(timeout: 5),
            "drawer did not close after tapping the toggle again")
    }
}
