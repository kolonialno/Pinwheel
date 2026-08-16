import DemoCatalog
import XCTest

/// Throwaway: the whole flow, once, on the final architecture.
final class FlowProbe: XCTestCase {
    func testTheWholeFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinwheelRecord", "-PinwheelPreview", Catalog.tray.id(.swiftUI)]
        app.launch()

        let open = app.buttons["Boost Post"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the demo never arrived")
        open.tap()
        Thread.sleep(forTimeInterval: 2)

        let region = app.descendants(matching: .any)["pinwheel.tray.value.Region"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5), "the boost tray never assembled")

        // The mini tray, and back.
        app.buttons["How it works"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(app.buttons["Back"].firstMatch.exists, "no way back out of the mini tray")
        app.buttons["Back"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.5)

        // A choice tray: pick one, it applies and pops.
        let pay = app.descendants(matching: .any)["pinwheel.tray.value.Pay with"].firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5), "no Pay with row")
        pay.tap()
        Thread.sleep(forTimeInterval: 2.5)
        app.descendants(matching: .any)["pinwheel.tray.choice.Pay with X Money"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(region.exists, "choosing should have come back to Boost Post")

        // The search tray: keyboard, typing, and a pull from the top.
        region.tap()
        Thread.sleep(forTimeInterval: 3)
        let search = app.descendants(matching: .any)["pinwheel.tray.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the search tray never opened")
        search.typeText("P")
        let first = app.descendants(matching: .any)["pinwheel.tray.country.Pakistan"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the list never filtered")
        Thread.sleep(forTimeInterval: 1)

        // Into the list first, then drag down from inside it: the keyboard goes with the finger and the
        // card's top must not move while it does.
        let inList = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        inList.press(forDuration: 0.15, thenDragTo: inList.withOffset(CGVector(dx: 0, dy: -260)))
        Thread.sleep(forTimeInterval: 1.5)
        inList.press(forDuration: 0.4, thenDragTo: inList.withOffset(CGVector(dx: 0, dy: 240)))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(search.exists, "scrolling the list must not have dismissed the tray")

        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 430)))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(search.exists, "pulling from the top should have dismissed it")
        XCTAssertTrue(open.exists, "and left the screen behind")
    }
}
