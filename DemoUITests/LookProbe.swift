import DemoCatalog
import XCTest

/// Throwaway: a look at the boost tray.
final class LookProbe: XCTestCase {
    func testTheBoostTray() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinwheelPreview", Catalog.tray.id(.swiftUI)]
        app.launch()
        let open = app.buttons["Boost Post"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let region = app.descendants(matching: .any)["pinwheel.tray.value.Region"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5), "the boost tray never assembled")
        Thread.sleep(forTimeInterval: 1.5)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "boost"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
