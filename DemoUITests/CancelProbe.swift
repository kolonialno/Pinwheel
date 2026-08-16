import DemoCatalog
import XCTest

/// Throwaway: a pull taken back, then one carried through.
final class CancelProbe: XCTestCase {
    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments = ["-PinwheelRecord", "-PinwheelPreview", Catalog.tray.id(.swiftUI)]
        app.launch()
        let open = app.buttons["Boost Post"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let region = app.descendants(matching: .any)["pinwheel.tray.value.Region"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        region.tap()
        let field = app.descendants(matching: .any)["pinwheel.tray.search"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the search tray never opened")
        field.typeText("an")
        let first = app.descendants(matching: .any)["pinwheel.tray.country.Andorra"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the list never filtered")
        Thread.sleep(forTimeInterval: 1)
        return first
    }

    func testAPullCarriedThrough() {
        let app = XCUIApplication()
        let first = openSearch(app)
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.descendants(matching: .any)["pinwheel.tray.search"].firstMatch.exists,
                       "a pull past the point dismisses")
    }
}
