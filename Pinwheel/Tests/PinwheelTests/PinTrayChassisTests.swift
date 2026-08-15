import SwiftUI
import XCTest
@testable import Pinwheel

/// Facts about the chassis read off the real views, because what broke here was invisible in the card's
/// own geometry: the card was right the whole time and the content inside it was not.
@MainActor
final class PinTrayChassisTests: XCTestCase {
    private func standing() -> (PinTrayOverlay, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 912))
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false

        let overlay = PinTrayOverlay(
            in: root,
            showing: AnyView(Color.clear.frame(height: 600).fixedSize(horizontal: false, vertical: true))
        )
        window.layoutIfNeeded()
        return (overlay, window)
    }

    // Coming back to the search tray with a query still typed, its content measured 1553 against a 641
    // card, so the chassis laid it out at 1553 and the card showed a window onto nothing.
    func testAnArrivingTrayTallerThanTheCardIsStillLaidOutToTheCard() {
        let (overlay, window) = standing()
        let card = overlay.cardHeight

        overlay.show(AnyView(Color.clear.frame(height: 2_000).fixedSize(horizontal: false, vertical: true)), isPush: true)
        overlay.trayFills(true)
        window.layoutIfNeeded()

        XCTAssertEqual(
            overlay.contentHeight,
            card,
            accuracy: 0.5,
            "a tray arriving into a card is the size of that card, however tall it measures"
        )
    }

    // Pushing into the search tray, its content was laid out at its own measured height — 245 against a
    // 642 card — so the search field, which rides the content's bottom edge, appeared mid-screen and
    // travelled to the bottom once the move resolved.
    func testTheArrivingContentIsLaidOutToTheCardRatherThanToItself() {
        let (overlay, window) = standing()
        let card = overlay.cardHeight

        overlay.show(AnyView(Color.clear.frame(height: 120).fixedSize(horizontal: false, vertical: true)), isPush: true)
        window.layoutIfNeeded()
        XCTAssertEqual(overlay.contentHeight, card, accuracy: 0.5, "at the moment it is mounted")

        // And it survives what arrives next: everything SwiftUI reports mid-move is drawn through the
        // same seam, which is where the mounted height was being undone.
        overlay.trayFills(true)
        overlay.settle(to: 120)
        window.layoutIfNeeded()
        XCTAssertEqual(
            overlay.contentHeight,
            card,
            accuracy: 0.5,
            "and after it reports on itself, so nothing anchored to its bottom jumps"
        )
    }
}
