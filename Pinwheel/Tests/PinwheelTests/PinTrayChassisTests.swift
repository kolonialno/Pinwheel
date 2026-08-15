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

        let overlay = PinTrayOverlay()
        overlay.install(over: root)
        overlay.present(AnyView(Color.clear.frame(height: 600).fixedSize(horizontal: false, vertical: true)))
        window.layoutIfNeeded()
        return (overlay, window)
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
