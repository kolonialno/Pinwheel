import SwiftUI
import XCTest
@testable import Pinwheel

/// The body is a plain `UIView`, so what it does is testable without an app, a scene or a host. That is
/// the whole reason containment is UIKit's job here.
@MainActor
final class PinTrayBodyTests: XCTestCase {
    private func rows(_ count: Int) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { row in
                    Text("Row \(row)").frame(maxWidth: .infinity)
                }
            }
        )
    }

    /// Sized by constraints inside a window, the way the card sizes it — not by a frame written on it,
    /// which hands the hosting view a height it never had to work out for itself.
    private func attachedBody(showing content: AnyView) -> PinTrayBodyView {
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
        window.rootViewController = parent
        window.isHidden = false

        let body = PinTrayBodyView(showing: content, in: parent)
        parent.view.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: parent.view.topAnchor),
            body.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
        ])
        window.layoutIfNeeded()
        return body
    }

    func testRowsShownAfterAttachAreLaidOutAsTallAsTheyMeasure() {
        let body = attachedBody(showing: rows(1))

        body.show(rows(60))
        body.superview?.layoutIfNeeded()

        XCTAssertEqual(
            body.scrollableHeight,
            body.contentHeight(fitting: 400),
            accuracy: 1,
            "rows swapped in after the body is standing still have to be laid out, or none can be touched"
        )
    }

    // The card follows the finger, so what the body reports is how far the finger has come — not how far
    // it moved since the last frame. Reporting the frame's slice moved the card 9pt across a 430pt drag,
    // because the offset is pinned back to the top between every one of them.
    func testAPullReportsHowFarTheFingerHasComeNotTheLastFrame() {
        let body = attachedBody(showing: rows(60))
        let reports = PinTrayBodyReports()
        body.coordinating = reports

        body.wasPulled(pastTheTop: 10)
        body.wasPulled(pastTheTop: 10)
        body.wasPulled(pastTheTop: 10)

        XCTAssertEqual(
            reports.pulls.last ?? 0,
            30,
            accuracy: 0.5,
            "three tenths of the way down is thirty points from where it started"
        )
    }
}
