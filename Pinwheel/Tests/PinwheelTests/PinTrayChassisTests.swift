import SwiftUI
import XCTest
@testable import Pinwheel

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

    func testTheCommitButtonHoldsItsSizeAndOpacityThroughAMove() throws {
        let deeper = PinTray("How it works") { Color.clear.frame(height: 300) }.commit("Got It") {}
        let boost = PinTray("Boost") { Color.clear.frame(height: 300) }.commit("Boost Post") {}

        let (overlay, window) = standing(deeper)
        window.layoutIfNeeded()
        overlay.show(boost, isPush: false)
        window.layoutIfNeeded()

        // A move settles on the same values either way, so what is in flight is what separates a
        // button holding from one dissolving.
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

    func testALeavingTrayIsTornDownOnlyOnceItHasTravelled() {
        let (overlay, window) = standing(PinTray("Boost") { Color.clear.frame(height: 300) })
        overlay.dismiss()
        window.layoutIfNeeded()
        XCTAssertNotNil(overlay.superview, "still on screen for as long as it is travelling")
    }
}
