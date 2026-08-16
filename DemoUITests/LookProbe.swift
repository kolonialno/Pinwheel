import DemoCatalog
import XCTest

/// Throwaway: a look at the boost tray.
final class LookProbe: XCTestCase {
    func testTheBoostTray() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinwheelRecord", "-PinwheelPreview", Catalog.tray.id(.swiftUI)]
        app.launch()
        let open = app.buttons["Boost Post"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let region = app.descendants(matching: .any)["pinwheel.tray.value.Region"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5), "the boost tray never assembled")
        Thread.sleep(forTimeInterval: 1.5)

        // A pull up has nowhere to go, so the card resists and comes back to where it stood.
        let before = region.frame.minY
        let middle = region.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.2, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -160)))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(region.frame.minY, before, accuracy: 0.5,
                       "a pull up must leave the tray where it stood")

        // A body that cannot scroll hands the drag to the card, so a fitting tray still drags away.
        let down = region.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        down.press(forDuration: 0.15, thenDragTo: down.withOffset(CGVector(dx: 0, dy: 420)))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(region.exists, "dragging down a tray that does not scroll must dismiss it")
        XCTAssertTrue(open.exists, "and leave the screen behind")

        open.tap()
        XCTAssertTrue(region.waitForExistence(timeout: 5), "the tray never came back")
        Thread.sleep(forTimeInterval: 1.5)

        func report(_ name: String, _ frame: CGRect) {
            print(String(format: "MEASURE %-22@ x %6.1f..%6.1f (w %5.1f)   y %6.1f..%6.1f (h %5.1f)",
                         name as NSString, frame.minX, frame.maxX, frame.width,
                         frame.minY, frame.maxY, frame.height))
        }
        let any = app.descendants(matching: .any)
        report("title", any.matching(NSPredicate(format: "identifier BEGINSWITH 'pinwheel.tray.Boost'")).firstMatch.frame)
        report("link.LearnMore", any["pinwheel.tray.link.Learn more"].firstMatch.frame)
        report("wheel", app.pickerWheels.firstMatch.frame)
        report("value.Region", any["pinwheel.tray.value.Region"].firstMatch.frame)
        report("value.PayWith", any["pinwheel.tray.value.Pay with"].firstMatch.frame)
        report("link.Terms", any["pinwheel.tray.link.Terms and Conditions"].firstMatch.frame)
        report("commit", app.buttons.matching(NSPredicate(format: "label == 'Boost Post'")).allElementsBoundByIndex
                            .filter { $0.frame.width > 300 }.first?.frame ?? .zero)
        report("app window", app.frame)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "boost"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
