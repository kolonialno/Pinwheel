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
