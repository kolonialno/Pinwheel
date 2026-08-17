import SwiftUI
import UIKit
import XCTest
@testable import Pinwheel

@MainActor
final class TrayOnlyOneTests: XCTestCase {
    private func spin(_ window: UIWindow, for seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }
    }

    func testATrayRescuedOnItsWayOutIsTheOneThatOpensNextTime() throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "the host app has no window scene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()

        let sync = PinTrayPathSync<Int>()
        let tray = { PinTray("Boost") { Color.clear.frame(height: 300) }.commit("Boost Post") {} }

        sync.sync(path: [0], from: presenter) { _ in tray() }
        spin(window, for: 0.6)

        let leaving = try XCTUnwrap(
            presenter.children.compactMap { $0 as? PinTrayChassis }.first,
            "a tray is standing"
        )

        // the path empties, so the tray starts leaving
        sync.sync(path: [], from: presenter) { _ in tray() }
        spin(window, for: 0.05)

        // a finger lands on it mid-flight, which is meant to bring it back
        leaving.cardWasTouched()
        spin(window, for: 0.5)

        sync.sync(path: [0], from: presenter) { _ in tray() }
        spin(window, for: 0.6)

        let trays = presenter.children.compactMap { $0 as? PinTrayChassis }
        XCTAssertEqual(
            trays.count, 1,
            "one tray stands at a time — reopening while the last is still leaving must reuse it, not stack: \(trays.count)"
        )
    }
}
