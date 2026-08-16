import DemoCatalog
import XCTest

/// Throwaway.
final class FlowProbe: XCTestCase {
    func testPullFromTheTopDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinwheelRecord", "-PinwheelPreview", Catalog.tray.id(.swiftUI)]
        app.launch()
        let open = app.buttons["Boost Post"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the demo never arrived")
        open.tap()
        Thread.sleep(forTimeInterval: 2)

        let region = app.descendants(matching: .any)["pinwheel.tray.value.Region"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5), "the boost tray never assembled")
        region.tap()
        Thread.sleep(forTimeInterval: 3)

        let search = app.descendants(matching: .any)["pinwheel.tray.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the search tray never opened")
        search.typeText("P")
        let first = app.descendants(matching: .any)["pinwheel.tray.country.Pakistan"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the list never filtered")
        Thread.sleep(forTimeInterval: 1)

        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 430)))
        Thread.sleep(forTimeInterval: 3)
    }
}
