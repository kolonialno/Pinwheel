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
        XCTAssertEqual(lifted.bottomInset, 336 + .spacing4)
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
        XCTAssertEqual(noIndicator.contentBottomInset, .spacing4)
    }
}

extension PinTrayGeometryTests {
    func testTheBackdropStandsWhileTheTrayDoesAndLeavesWithIt() {
        let room = PinTrayGeometry.Room(containerHeight: 900)
        let standing = PinTrayGeometry(contentHeight: 400, room: room)
        let leaving = PinTrayGeometry(contentHeight: 400, room: room, phase: .leaving)
        let arriving = PinTrayGeometry(contentHeight: 400, room: room, phase: .arriving)

        XCTAssertEqual(standing.dimming, 1, "a tray on screen is read against a dimmed backdrop")
        XCTAssertEqual(arriving.dimming, 1, "and one on its way in is arriving against that backdrop")
        XCTAssertEqual(leaving.dimming, 0, "a tray on its way out takes the backdrop with it")
    }

    func testContentPassesBehindWhatFloatsAndStandsOffACommitButton() {
        XCTAssertEqual(
            PinTrayGeometry.clearanceAboveAccessory(floats: true), .spacing2,
            "content passes behind something floating, so it needs a hairline"
        )
        XCTAssertEqual(
            PinTrayGeometry.clearanceAboveAccessory(floats: false), traySectionGap,
            "a button is not floated over, so content stands off it like any other group"
        )
    }
}
