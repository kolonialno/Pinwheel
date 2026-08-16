import XCTest
@testable import Pinwheel

@MainActor
final class PinTrayGeometryTests: XCTestCase {
    private let screen = PinTrayGeometry.Room(
        containerHeight: 912,
        safeAreaTop: 62,
        safeAreaBottom: 34,
        displayCornerRadius: 62
    )

    private func geometry(
        contentHeight: CGFloat = 300,
        keyboardInset: CGFloat = 0,
        dragOffset: CGFloat = 0,
        phase: PinTrayGeometry.Phase = .resting,
        standsOnKeyboard: Bool = true
    ) -> PinTrayGeometry {
        PinTrayGeometry(
            contentHeight: contentHeight,
            room: screen,
            keyboardInset: keyboardInset,
            dragOffset: dragOffset,
            phase: phase,
            standsOnKeyboard: standsOnKeyboard
        )
    }

    func testATrayArrivesFromBelowItsOwnBottomEdge() {
        let arriving = geometry(phase: .arriving)
        XCTAssertEqual(arriving.translation, arriving.height + arriving.bottomInset)
        XCTAssertGreaterThan(arriving.translation, 0, "a tray travels up to its place rather than appearing there")
    }

    func testATrayLeavesTheWayItArrived() {
        XCTAssertEqual(geometry(phase: .leaving).translation, geometry(phase: .arriving).translation)
    }

    func testAStandingTrayCarriesNoTranslationOfItsOwn() {
        XCTAssertEqual(geometry(phase: .resting).translation, 0)
    }

    func testADragDownCarriesTheTrayWithIt() {
        XCTAssertEqual(geometry(dragOffset: 120).translation, 120)
    }

    func testAPullUpResistsAndIsBounded() {
        XCTAssertEqual(PinTrayGeometry.travel(forDrag: 200), 200, "a tray on its way out follows the finger")

        let gentle = PinTrayGeometry.travel(forDrag: -40)
        XCTAssertLessThan(gentle, 0, "a pull up lifts the tray")
        XCTAssertGreaterThan(gentle, -40, "but by less than the finger came")

        XCTAssertLessThan(PinTrayGeometry.travel(forDrag: -400), gentle, "pulling harder lifts it further")
        XCTAssertGreaterThan(
            PinTrayGeometry.travel(forDrag: -4000),
            -trayLift,
            "however hard it is pulled, the strip above the tray stays reachable"
        )
    }

    func testATrayStandingOnTheKeyboardClearsItByMoreThanTheScreensEdge() {
        let lifted = geometry(keyboardInset: 336)
        XCTAssertEqual(lifted.bottomInset, 336 + .spacingL)
        XCTAssertGreaterThan(lifted.bottomInset - 336, geometry().bottomInset)
    }

    func testATrayThatIsNotEditingRestsAtTheBottomWhileTheKeyboardLeavesOverIt() {
        let resting = geometry(keyboardInset: 336, standsOnKeyboard: false)
        XCTAssertEqual(resting.bottomInset, trayBottomMargin, "only the keyboard moves on the way out")
        XCTAssertEqual(resting.bottomCornerRadius, screen.displayCornerRadius)
    }

    func testATrayTallerThanTheRoomStandsAtTheRoomsHeight() {
        let tall = geometry(contentHeight: 5_000)
        XCTAssertEqual(tall.height, 912 - 62 - trayBackdropReach - trayBottomMargin)
    }

    func testATrayShorterThanTheRoomStandsAtItsContentsHeight() {
        XCTAssertEqual(geometry(contentHeight: 269).height, 269)
    }

    func testATrayOnTheBottomEdgeTakesTheDisplaysOwnCorner() {
        XCTAssertEqual(geometry().bottomCornerRadius, 62)
    }

    func testATrayLiftedOffTheBottomLosesTheDisplaysCorner() {
        XCTAssertEqual(geometry(keyboardInset: 336).bottomCornerRadius, trayTopRadius)
    }

    func testContentClearsTheHomeIndicatorLessTheMarginTheTrayAlreadyStandsOff() {
        XCTAssertEqual(geometry().contentBottomInset, 34 - trayBottomMargin)
    }

    func testContentKeepsAFloorOfClearanceWhereThereIsNoHomeIndicator() {
        let noIndicator = PinTrayGeometry(
            contentHeight: 300,
            room: PinTrayGeometry.Room(containerHeight: 912, safeAreaTop: 20, safeAreaBottom: 0)
        )
        XCTAssertEqual(noIndicator.contentBottomInset, .spacingL)
    }
}
