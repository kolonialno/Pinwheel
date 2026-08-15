import SwiftUI
import XCTest
@testable import Pinwheel

/// Layout facts read off what the tray actually rendered, through the capture engine — the same
/// DisplayList the Figma capture reads. A screenshot cannot answer these and guessing at pixels in one
/// is worse than not measuring at all.
@MainActor
final class PinTrayLayoutTests: XCTestCase {
    private let card = CGSize(width: 420, height: 600)
    /// A colour nothing else in the tray uses, so the node is findable by its fill alone.
    private let markerFill = Color(red: 1, green: 0, blue: 1)

    private func nodes(in tray: some SwiftUI.View) throws -> [FigmaNode] {
        let document = try XCTUnwrap(
            PinDisplayListCapture.document(tray, name: "tray", size: card, screenHeight: card.height),
            "the tray captured nothing"
        )
        func flatten(_ node: FigmaNode) -> [FigmaNode] {
            [node] + node.children.flatMap(flatten)
        }
        return flatten(document.root)
    }

    private func marker(in tray: some SwiftUI.View) throws -> FigmaNode {
        let magenta = try nodes(in: tray).filter {
            guard let fill = $0.fill else { return false }
            return fill.r > 0.9 && fill.g < 0.1 && fill.b > 0.9
        }
        // The smallest one is the rectangle itself; a container may inherit its fill.
        return try XCTUnwrap(magenta.min(by: { $0.h < $1.h }), "the marker never rendered")
    }

    private func fillingTray<Floating: SwiftUI.View>(
        @ViewBuilder floating: @escaping () -> Floating
    ) -> some SwiftUI.View {
        let phase = PinTrayPhase()
        phase.standingRoom = card.height
        return PinTray("Region") {
            ScrollView { Color.clear.frame(height: 2_000) }
                .overlay(alignment: .bottom, content: floating)
        }
        .detent(.filling)
        .environment(\.pinTrayPhase, phase)
    }

    // And the card's whole height is content: a filling tray hands its content the full card, or
    // anything anchored to the content's bottom floats short of the card's edge.
    func testAFillingTrayHandsItsContentTheWholeCard() throws {
        let tray = fillingTray {
            Rectangle().fill(self.markerFill).frame(height: .minimumControlHeight)
        }
        let field = try marker(in: tray)

        XCTAssertEqual(field.y + field.h, card.height, accuracy: 0.5, "the content reaches the card's edge")
    }
}
