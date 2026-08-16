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

        var rows: [(CGRect, String)] = []
        for kind in [XCUIElement.ElementType.staticText, .button, .image, .other] {
            for element in app.descendants(matching: kind).allElementsBoundByIndex {
                guard element.exists, element.frame.height > 0, element.frame.width > 40 else { continue }
                let name = element.identifier.isEmpty ? element.label : element.identifier
                guard !name.isEmpty else { continue }
                rows.append((element.frame, "\(kind.rawValue) \(name)"))
            }
        }
        rows.sort { $0.0.minY < $1.0.minY }
        var report = "GEOMETRY\n"
        var previousMaxY: CGFloat?
        for (frame, name) in rows {
            if let previous = previousMaxY, frame.minY - previous > 0.5 {
                report += String(format: "        ---- gap %.1f ----\n", frame.minY - previous)
            }
            report += String(format: "  y %7.1f  h %6.1f  x %6.1f w %6.1f  %@\n",
                             frame.minY, frame.height, frame.minX, frame.width, name)
            previousMaxY = max(previousMaxY ?? 0, frame.maxY)
        }
        let dump = XCTAttachment(string: report)
        dump.name = "geometry"
        dump.lifetime = .keepAlways
        add(dump)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "boost"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
