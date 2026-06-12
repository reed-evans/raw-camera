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
        let manual = manualSegment(near: drawerLabel, in: app)
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

    /// Landscape regression: revealing the manual sliders must not balloon the
    /// rotated drawer (the transposed reservation frame once fed the panel's
    /// long dimension to greedy slider rows, blowing it up to the full screen).
    @MainActor
    func testLandscapeManualSlidersStayUnderModeToggle() {
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launch()

        let show = app.buttons["Show settings"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), "settings toggle not found")

        // Rotate AFTER launch: the running app reliably receives the orientation
        // notification, whereas a pre-launch set can be swallowed when the
        // simulator's orientation state is stale (seen after manual simctl runs).
        XCUIDevice.shared.orientation = .landscapeLeft
        show.tap()

        let exposure = app.staticTexts["EXPOSURE"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5), "drawer did not open")
        // Landscape renders the label sideways, so its on-screen box is taller
        // than wide. Guards against the rotation never engaging, which would
        // make the rest of this test vacuously pass against portrait layout.
        XCTAssertGreaterThan(
            exposure.frame.height, exposure.frame.width,
            "landscape rotation did not engage")

        let manual = manualSegment(near: exposure, in: app)
        XCTAssertTrue(manual.waitForExistence(timeout: 2), "exposure A/M segment not found")
        manual.tap()

        let iso = app.staticTexts["ISO"]
        XCTAssertTrue(iso.waitForExistence(timeout: 3), "manual sliders did not appear")
        let distance = hypot(
            iso.frame.midX - manual.frame.midX,
            iso.frame.midY - manual.frame.midY)
        XCTAssertLessThan(
            distance, 200,
            "manual sliders appeared \(Int(distance))pt from the A/M toggle (panel blow-up)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "landscape-manual-exposure"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Regression: revealing the zoom slider while the drawer is open must
    /// place it above the panel on the FIRST reveal, not on top of the drawer.
    @MainActor
    func testZoomSliderClearsOpenDrawerOnFirstReveal() {
        let app = XCUIApplication()
        app.launch()

        let show = app.buttons["Show settings"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), "settings toggle not found")
        show.tap()

        let monitor = app.staticTexts["MONITOR"]
        XCTAssertTrue(monitor.waitForExistence(timeout: 5), "drawer did not open")
        // Let the drawer's opening spring settle: nearest-element math against
        // mid-animation frames can land the tap on the row below (ZEBRA).
        Thread.sleep(forTimeInterval: 0.6)

        // Flip the ZOOM monitor switch (switches carry no labels — pick the
        // one nearest the ZOOM caption).
        let zoomLabel = app.staticTexts["ZOOM"]
        XCTAssertTrue(zoomLabel.waitForExistence(timeout: 2), "ZOOM row not found")
        element(app.switches, nearest: zoomLabel).tap()

        XCTAssertTrue(
            app.staticTexts["1.0×"].waitForExistence(timeout: 3),
            "zoom readout missing — wrong switch flipped or slider absent")
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 3), "zoom slider did not appear")
        XCTAssertLessThan(
            slider.frame.maxY, monitor.frame.minY,
            "zoom slider overlaps the open drawer on first reveal")
    }

    /// The "M" segment nearest a section label. Every section has its own A/M
    /// segment and accessibility order is not stable across orientations, so
    /// `firstMatch` can land on the wrong section's switch.
    @MainActor
    private func manualSegment(near sectionLabel: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let anchor = sectionLabel.frame
        let candidates = app.buttons.matching(identifier: "M").allElementsBoundByIndex
        let nearest = candidates.min { a, b in
            hypot(a.frame.midX - anchor.midX, a.frame.midY - anchor.midY)
                < hypot(b.frame.midX - anchor.midX, b.frame.midY - anchor.midY)
        }
        return nearest ?? app.buttons["M"].firstMatch
    }

    /// The element in `query` whose frame center is nearest the anchor's.
    @MainActor
    private func element(_ query: XCUIElementQuery, nearest anchor: XCUIElement) -> XCUIElement {
        let center = anchor.frame
        let candidates = query.allElementsBoundByIndex
        let nearest = candidates.min { a, b in
            hypot(a.frame.midX - center.midX, a.frame.midY - center.midY)
                < hypot(b.frame.midX - center.midX, b.frame.midY - center.midY)
        }
        return nearest ?? query.firstMatch
    }
}
