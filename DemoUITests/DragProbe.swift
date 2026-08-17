import DemoCatalog
import XCTest

/// Throwaway. A short drag that springs back, then a long one that dismisses.
final class DragProbe: XCTestCase {
    func testDragging() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinwheelPreview", Catalog.tray.id(.swiftUI)]
        app.launch()
        let open = app.buttons["Boost Post"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pinwheel.tray.value.Region"].firstMatch
            .waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 60)))
        Thread.sleep(forTimeInterval: 2)
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 500)))
        Thread.sleep(forTimeInterval: 3)
    }
}
