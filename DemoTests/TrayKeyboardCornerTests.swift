import SwiftUI
import UIKit
import XCTest
@testable import Pinwheel

/// A tray resting on the screen's bottom edge is nested in the display's own corner and takes its
/// radius. Lifted off it by a keyboard, it is nested in nothing, so that radius reads as an oversized
/// corner and it takes its own instead.
///
/// Hosted, because a keyboard needs the app's scene machinery: a hostless bundle draws the tray fine
/// but its `keyboardLayoutGuide` never moves, so the branch that gets this wrong is never taken.
@MainActor
final class TrayKeyboardCornerTests: XCTestCase {
    private func field(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let found = field(in: subview) { return found }
        }
        return nil
    }

    private func settle(_ window: UIWindow, until reached: () -> Bool) {
        for _ in 0..<200 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
            if reached() { return }
        }
    }

    func testATrayRidingTheKeyboardWearsItsOwnCornersRatherThanTheDisplays() throws {
        // The window has to belong to the app's own scene, or its keyboard layout guide tracks nothing
        // and the card never lifts — which reads exactly like the bug being absent.
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "the host app has no window scene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()

        let boost = PinTray("Boost") { Color.clear.frame(height: 300) }.commit("Boost Post") {}
        let region = PinTray("Region") { Editable().frame(height: 44) }.detent(.filling)

        let overlay = PinTrayOverlay(in: root, showing: boost)
        window.layoutIfNeeded()
        settle(window) { overlay.bottomCornerRadius > 0 }

        XCTAssertEqual(
            overlay.bottomCornerRadius, UIScreen.main.pinDisplayCornerRadius, accuracy: 1,
            "resting on the floor, it is nested in the display's own corner"
        )

        overlay.show(region, isPush: true)
        window.layoutIfNeeded()
        let editable = try XCTUnwrap(field(in: overlay), "the region tray stands something to type in")
        let took = editable.becomeFirstResponder()
        XCTAssertTrue(took, "the field refused first responder")
        XCTAssertTrue(editable.isFirstResponder, "the field is not editing")
        XCTAssertNotNil(editable.window, "the field is not in a window")

        settle(window) { overlay.cardBottom < window.bounds.height - 100 }
        XCTAssertLessThan(
            overlay.cardBottom, window.bounds.height - 100,
            "the keyboard never lifted the card, so this proves nothing"
        )

        XCTAssertEqual(
            overlay.bottomCornerRadius, trayTopRadius, accuracy: 1,
            "lifted off the floor, it is nested in nothing and wears its own corner"
        )
    }
}

private struct Editable: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField { UITextField() }
    func updateUIView(_ view: UITextField, context: Context) {}
}
