import SwiftUI
import XCTest
@testable import Pinwheel

/// Facts about the chassis, read off the views it builds. Containment is its job, so these are ordinary
/// objects with ordinary frames and nothing has to be inferred from a picture.
@MainActor
final class PinTrayChassisTests: XCTestCase {
    private func standing(_ tray: PinTray) -> (PinTrayOverlay, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 912))
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false

        let overlay = PinTrayOverlay(in: root, showing: tray)
        window.layoutIfNeeded()
        return (overlay, window)
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let found = view as? UIScrollView { return found }
        for subview in view.subviews {
            if let found = scrollView(in: subview) { return found }
        }
        return nil
    }

    // The body is the only thing in a tray that scrolls, and it takes everything under the title bar —
    // which is what puts anything standing at its bottom on the card's bottom edge.
    func testTheBodyTakesEverythingBelowTheTitleBar() throws {
        let (overlay, window) = standing(
            PinTray("Region") { Color.clear.frame(height: 2_000) }.detent(.filling)
        )
        window.layoutIfNeeded()

        let body = try XCTUnwrap(scrollView(in: overlay), "a tray has a scrolling body")
        let inCard = body.convert(body.bounds, to: overlay)

        XCTAssertGreaterThan(inCard.minY, 0, "the title bar stands above it")
        XCTAssertEqual(inCard.maxY, overlay.cardBottom, accuracy: 1, "and it runs to the card's own edge")
    }

    // Whatever floats at the bottom stands over the body, and the body keeps room below its last row so
    // that row can still be read past it.
    func testTheBodyKeepsRoomBelowItsLastRowForWhatFloatsOverIt() throws {
        let (overlay, window) = standing(
            PinTray("Region") { Color.clear.frame(height: 2_000) }
                .detent(.filling)
                .floating { Color.clear.frame(height: 48) }
        )
        window.layoutIfNeeded()

        let body = try XCTUnwrap(scrollView(in: overlay), "a tray has a scrolling body")
        XCTAssertGreaterThan(body.contentInset.bottom, 48, "the field's own height, and the gaps around it")
    }

    private func accessories(in view: UIView) -> [PinTrayLeafView] {
        if let leaf = view as? PinTrayLeafView { return leaf.frame.minY > 0 ? [leaf] : [] }
        return view.subviews.flatMap { accessories(in: $0) }
    }

    // Both trays draw the same button in the same place, so it holds through a move: solid from the
    // first frame and at its own size. Dissolving one into the other lightened the pill to 0.75 half way
    // through, and the zoom that gives the content its depth drew it at 1.10.
    func testTheCommitButtonHoldsItsSizeAndOpacityThroughAMove() throws {
        let deeper = PinTray("How it works") { Color.clear.frame(height: 300) }.commit("Got It") {}
        let boost = PinTray("Boost") { Color.clear.frame(height: 300) }.commit("Boost Post") {}

        let (overlay, window) = standing(deeper)
        window.layoutIfNeeded()
        overlay.show(boost, isPush: false)
        window.layoutIfNeeded()

        // What a move settles on is the same either way; what separates holding from dissolving is what
        // is in flight, so the animations themselves are what this reads.
        let buttons = accessories(in: overlay)
        let inFlight = buttons.map { Set($0.layer.animationKeys() ?? []) }
        XCTAssertEqual(buttons.count, 2, "the button arriving and the one being left")
        XCTAssertEqual(
            inFlight.filter(\.isEmpty).count, 1,
            "the arriving button holds, so nothing about it is in flight: \(inFlight)"
        )
        XCTAssertTrue(
            inFlight.allSatisfy { !$0.contains("transform") },
            "and neither carries the content's zoom: \(inFlight)"
        )
    }

    // A button standing where a search field stood is a different thing arriving, so it fades in like
    // the rest of the tray. Only where both trays put the same button in the same place does it hold.
    func testAButtonArrivingWhereSomethingElseStoodFadesInRatherThanAppearing() throws {
        let region = PinTray("Region") { Color.clear.frame(height: 2_000) }
            .detent(.filling)
            .floating { Color.clear.frame(height: 48) }
        let boost = PinTray("Boost") { Color.clear.frame(height: 300) }
            .commit("Boost Post") {}

        let (overlay, window) = standing(region)
        window.layoutIfNeeded()
        overlay.show(boost, isPush: false)
        window.layoutIfNeeded()

        let buttons = accessories(in: overlay)
        let inFlight = buttons.map { Set($0.layer.animationKeys() ?? []) }
        XCTAssertEqual(buttons.count, 2, "the button arriving and the field being left")
        XCTAssertEqual(
            inFlight.filter(\.isEmpty).count, 0,
            "neither holds: what arrives is a different thing, so it fades in: \(inFlight)"
        )
    }

    // A leaving tray is torn down when its travel ends, not on a timer beside it.
    func testALeavingTrayIsTornDownOnlyOnceItHasTravelled() {
        let (overlay, window) = standing(PinTray("Boost") { Color.clear.frame(height: 300) })
        overlay.dismiss()
        window.layoutIfNeeded()
        XCTAssertNotNil(overlay.superview, "still on screen for as long as it is travelling")
    }
}
