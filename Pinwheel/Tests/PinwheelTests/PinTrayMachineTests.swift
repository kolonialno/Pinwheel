import XCTest
@testable import Pinwheel

/// Each of these is a state that broke, in the order it was found by filming, instrumenting and
/// measuring. They are here so the next change has to argue with them rather than rediscover them.
@MainActor
final class PinTrayMachineTests: XCTestCase {
    private let screen = PinTrayGeometry.Room(
        containerHeight: 912,
        safeAreaTop: 62,
        safeAreaBottom: 34,
        displayCornerRadius: 62
    )

    private func machine(standing height: CGFloat = 641, edits: Bool = false) -> PinTrayMachine {
        var machine = PinTrayMachine(room: screen)
        _ = machine.handle(.presented(contentHeight: height))
        if edits {
            _ = machine.handle(.moved(contentHeight: height, edits: true, isPush: true))
            _ = machine.handle(.keyboardMeasured(311))
        }
        return machine
    }

    // A transform assigned outside its animation put the tray on screen already arrived.
    func testATrayArrivesFromBelowItsOwnBottomEdge() {
        var machine = PinTrayMachine(room: screen)
        let reaction = machine.handle(.presented(contentHeight: 641))
        let from = try! XCTUnwrap(reaction.from)
        XCTAssertGreaterThan(from.translation, 0, "it starts below its place")
        XCTAssertEqual(reaction.to.translation, 0, "and travels to it")
        XCTAssertEqual(reaction.timeline, .spring(bounce: trayResizeBounce))
    }

    // Pushing into a tray that edits, the card shrank with no keyboard under it yet: its top fell to
    // the floor and climbed back once the keyboard arrived.
    func testATrayAboutToEditHoldsStillUntilTheKeyboardMoves() {
        var machine = machine()
        let standing = machine.geometry

        let push = machine.handle(.moved(contentHeight: 456, edits: true, isPush: true))
        XCTAssertEqual(machine.phase, .awaitingKeyboard)
        XCTAssertEqual(push.timeline, .carriedByKeyboard, "the keyboard owns this move, so we start nothing")

        let opening = machine.handle(.keyboardMeasured(311))
        XCTAssertEqual(opening.timeline, .carriedByKeyboard)
        let height = screen.containerHeight
        let top = { (g: PinTrayGeometry) in height - g.bottomInset - g.height }
        XCTAssertLessThan(top(opening.to), top(standing), "the top only ever travels up")
    }

    // The same push, seen as the whole journey: no state along the way sends the top downward.
    func testTheTopNeverReversesOnTheWayToTheKeyboard() {
        var machine = machine()
        let height = screen.containerHeight
        var tops = [height - machine.geometry.bottomInset - machine.geometry.height]
        for event in [PinTrayMachine.Event.moved(contentHeight: 456, edits: true, isPush: true),
                      .keyboardMeasured(311),
                      .keyboardMeasured(311)] {
            let reaction = machine.handle(event)
            tops.append(height - reaction.to.bottomInset - reaction.to.height)
        }
        XCTAssertEqual(tops, tops.sorted(by: >), "the top descends at no point: \(tops)")
    }

    // Unmounting the tray tore the field out from under the keyboard, so it vanished with no animation
    // for the card to travel beside.
    func testLeavingAnEditingTrayDismissesTheKeyboardDeliberately() {
        var machine = machine(edits: true)
        let pop = machine.handle(.moved(contentHeight: 641, edits: false, isPush: false))
        XCTAssertEqual(pop.effects, [.dismissKeyboard])
    }

    // Coming back from the search tray landed the card at 509pt — a height belonging to nothing, half
    // way between the two trays. The reaction was computed while the keyboard was still up, and applied
    // after dismissing it had already re-laid everything out, so the stale answer won.
    func testComingBackFromAnEditingTrayReturnsToTheHeightItLeftFrom() {
        var machine = machine()
        let standing = machine.geometry.height

        _ = machine.handle(.moved(contentHeight: 456, edits: true, isPush: true))
        _ = machine.handle(.keyboardMeasured(311))
        _ = machine.handle(.keyboardMeasured(311))

        // The field is still first responder at the moment the pop is reported: the keyboard has been
        // asked to go, not yet gone.
        let pop = machine.handle(.moved(contentHeight: standing, edits: true, isPush: false))
        XCTAssertEqual(pop.to.height, standing, "it comes back to the height it left from")
    }

    // The rule underneath: an effect the machine commands is part of its own state that same turn, so
    // whatever the outside world does about it can only ever agree.
    func testCommandingTheKeyboardAwayCountsAsTheKeyboardLeaving() {
        var machine = machine(edits: true)
        let pop = machine.handle(.moved(contentHeight: 641, edits: true, isPush: false))

        XCTAssertEqual(pop.effects, [.dismissKeyboard])
        XCTAssertEqual(machine.keyboard.height, 0, "it does not go on believing the keyboard is up")
        XCTAssertEqual(
            machine.handle(.keyboardMeasured(0)).to,
            pop.to,
            "the keyboard reporting what it was told changes nothing, so arrival order cannot matter"
        )
    }

    // The whole point of a filling tray: its top is a constant, so tapping the search field again
    // cannot shoot it anywhere. Only the bottom travels, riding the keyboard down to the floor.
    func testAFillingTrayKeepsItsTopWhereverTheKeyboardIs() {
        var machine = PinTrayMachine(room: screen)
        _ = machine.handle(.fillsReported(true))
        _ = machine.handle(.presented(contentHeight: 0))
        _ = machine.handle(.moved(contentHeight: 0, edits: true, isPush: true))

        let height = screen.containerHeight
        let top = { (geometry: PinTrayGeometry) in height - geometry.bottomInset - geometry.height }
        var tops: [CGFloat] = []
        var bottoms: [CGFloat] = []
        for measured in [311, 311, 240, 160, 80, 0, 0, 311] as [CGFloat] {
            let reaction = machine.handle(.keyboardMeasured(measured))
            tops.append(top(reaction.to))
            bottoms.append(reaction.to.bottomInset)
        }
        XCTAssertEqual(Set(tops).count, 1, "the top never moves: \(tops)")
        XCTAssertEqual(bottoms.min(), trayBottomMargin, "and the bottom stops at the floor: \(bottoms)")
    }

    // How a tray stands arrives from SwiftUI whenever SwiftUI gets round to it — measured, 157ms before
    // the move it describes. Drawing on arrival sent the card to the floor and back: 262 -> 602 -> 76.
    func testATrayLearningItFillsDrawsNothingUntilTheNextEventCarriesIt() {
        var machine = machine()
        let standing = machine.geometry
        _ = machine.handle(.moveBegan(isPush: true))

        let reported = machine.handle(.fillsReported(true))
        XCTAssertEqual(reported.to, standing, "learning it fills moves nothing on its own")
        XCTAssertEqual(reported.timeline, .carriedByKeyboard, "and starts nothing of ours")

        let moved = machine.handle(.moved(contentHeight: 200, edits: false, isPush: true))
        XCTAssertGreaterThan(moved.to.height, 200, "the next event stands it in the room it has")
    }

    // Deferring it to the next event assumed one was coming. With a hardware keyboard attached none is
    // — the software keyboard never appears — so the search tray stood at its content's height instead
    // of filling the room, for as long as it was open.
    func testATrayLearningItFillsAfterItHasArrivedStandsInTheRoomAtOnce() {
        var machine = machine()
        _ = machine.handle(.moveBegan(isPush: true))
        _ = machine.handle(.moved(contentHeight: 200, edits: false, isPush: true))

        let reaction = machine.handle(.fillsReported(true))
        XCTAssertGreaterThan(reaction.to.height, 200, "a tray that has arrived stands up when it learns")
    }

    // SwiftUI hands the flag over whenever it gets round to it, which is sometimes before the move it
    // describes and sometimes after. The tray ends up filling either way.
    func testATrayFillsTheRoomWhicheverOrderItsFlagAndItsMoveArriveIn() {
        for flagFirst in [true, false] {
            var machine = machine()
            _ = machine.handle(.moveBegan(isPush: true))
            if flagFirst { _ = machine.handle(.fillsReported(true)) }
            let moved = machine.handle(.moved(contentHeight: 200, edits: false, isPush: true))
            let standing = flagFirst ? moved : machine.handle(.fillsReported(true))

            XCTAssertGreaterThan(
                standing.to.height,
                500,
                "flag \(flagFirst ? "before" : "after") the move: it stands in the room either way"
            )
        }
    }

    // Holding still until the keyboard moves is a bet that it is coming. With a hardware keyboard
    // attached the field takes focus and the software keyboard never appears, so the bet never settles
    // and the search tray sat at its content's height — 245 of a possible 834 — for as long as it was
    // open.
    func testATrayWaitingForAKeyboardThatNeverComesStandsUpAnyway() {
        var machine = machine()
        _ = machine.handle(.moveBegan(isPush: true))
        _ = machine.handle(.fillsReported(true))
        _ = machine.handle(.moved(contentHeight: 245, edits: true, isPush: true))
        XCTAssertEqual(machine.phase, .awaitingKeyboard, "it is waiting")

        let standing = machine.handle(.keyboardNeverCame)
        XCTAssertEqual(machine.phase, .standing, "it gives up waiting")
        XCTAssertTrue(machine.fills, "and takes up what the arriving tray said about itself")
        XCTAssertEqual(standing.to.height, machine.geometry.height, accuracy: 0.5)
        XCTAssertEqual(
            standing.to.height,
            screen.containerHeight - screen.safeAreaTop - trayBackdropReach - trayBottomMargin,
            accuracy: 0.5,
            "standing in the room it has, not at its content"
        )
    }

    // The whole way in, measured off the app: 641 -> 245 -> 828, a collapse to the arriving tray's
    // content height before it stood up. SwiftUI measures the arriving content mid-move, and a value
    // arriving mid-move must be recorded rather than drawn — whichever value it is.
    func testPushingIntoATrayNeverDropsItsTopOnTheWayIn() {
        var machine = machine()
        let height = screen.containerHeight
        let top = { (geometry: PinTrayGeometry) in height - geometry.bottomInset - geometry.height }
        var tops = [top(machine.geometry)]

        for event in [PinTrayMachine.Event.moveBegan(isPush: true),
                      .fillsReported(true),
                      .contentResized(245),
                      .moved(contentHeight: 245, edits: true, isPush: true),
                      .keyboardMeasured(311)] {
            tops.append(top(machine.handle(event).to))
        }

        XCTAssertEqual(tops, tops.sorted(by: >), "the top never descends on the way in: \(tops)")
    }

    // Tapping the space above the card dismisses the tray, so the card may never take that space.
    // Filling it left a 14pt strip between the safe area and the card — measured, a tap aimed there
    // landed on the card instead, and the only way out was the header.
    func testNoTrayEverCoversTheSpaceThatDismissesIt() {
        var machine = machine()
        _ = machine.handle(.moveBegan(isPush: true))
        _ = machine.handle(.fillsReported(true))
        _ = machine.handle(.moved(contentHeight: 245, edits: true, isPush: true))

        let height = screen.containerHeight
        for measured in [0, 311, 0] as [CGFloat] {
            let reaction = machine.handle(.keyboardMeasured(measured))
            let top = height - reaction.to.bottomInset - reaction.to.height
            XCTAssertGreaterThanOrEqual(
                top - screen.safeAreaTop,
                .minimumControlHeight,
                "the strip above the card stays big enough to hit, keyboard at \(measured)"
            )
        }
    }

    func testLeavingATrayThatWasNotEditingAsksNothingOfTheKeyboard() {
        var machine = machine()
        let pop = machine.handle(.moved(contentHeight: 456, edits: false, isPush: false))
        XCTAssertEqual(pop.effects, [])
    }

    // Our spring ran against the keyboard's own animation, and the second replaced the first: the
    // dismissal read as two chained steps rather than one motion.
    func testAMovingKeyboardAlwaysOwnsTheTimeline() {
        var machine = machine(edits: true)
        XCTAssertEqual(machine.handle(.keyboardMeasured(0)).timeline, .carriedByKeyboard)
        XCTAssertEqual(machine.handle(.keyboardMeasured(311)).timeline, .carriedByKeyboard)
    }

    func testASettledKeyboardOwnsNothing() {
        var machine = machine(edits: true)
        _ = machine.handle(.keyboardMeasured(311))
        XCTAssertEqual(machine.handle(.contentResized(300)).timeline, .spring(bounce: 0))
    }

    // Dragging the list to put the keyboard away, every sample arrived twice — once as moving and once
    // as settled — and the settled one started a spring at 60fps against a keyboard still under the
    // finger. Measured, the card's top wandered 116 -> 83 -> 116 while it should not have moved at all.
    func testAReactionThatChangesNothingStartsNothing() {
        var machine = machine(edits: true)
        let settled = machine.handle(.keyboardMeasured(311))
        XCTAssertEqual(settled.to, machine.geometry, "nothing about the tray changed")
        XCTAssertEqual(
            settled.timeline,
            .carriedByKeyboard,
            "so nothing of ours starts; a spring here fights whatever is still moving"
        )
    }

    // A search resizing per keystroke moved the card 13,174pt across 45 reversals, and the bounce is
    // what put the reversals there.
    func testContentSettlingCarriesNoBounce() {
        var machine = machine()
        XCTAssertEqual(machine.handle(.contentResized(300)).timeline, .spring(bounce: 0))
    }

    func testADragTracksTheFingerWithNoAnimationAndNeverLiftsPastItsPlace() {
        var machine = machine()
        XCTAssertEqual(machine.handle(.dragged(120)).timeline, .immediate)
        XCTAssertEqual(machine.geometry.translation, 120)
        _ = machine.handle(.dragged(-80))
        XCTAssertEqual(machine.geometry.translation, 0, "a drag upward does not lift it")
    }

    func testAReleasedDragSpringsBackUnlessItWentFarEnough() {
        var machine = machine()
        _ = machine.handle(.dragged(40))
        let held = machine.handle(.released(velocity: 0, dismissBeyond: 200))
        XCTAssertFalse(held.dismisses)

        _ = machine.handle(.dragged(300))
        let let_go = machine.handle(.released(velocity: 0, dismissBeyond: 200))
        XCTAssertTrue(let_go.dismisses)
        XCTAssertGreaterThan(let_go.to.translation, 0, "it leaves the way it arrived")
    }

    func testAFlickDismissesEvenFromCloseBy() {
        var machine = machine()
        _ = machine.handle(.dragged(20))
        XCTAssertTrue(machine.handle(.released(velocity: 2_000, dismissBeyond: 200)).dismisses)
    }

    // Tapping the backdrop over an editing tray lurched the card two thirds of the way down and then
    // deleted it off the screen. Three reactions had fought over the same property inside 24ms, and the
    // last one to land told the leaving tray to stay where it was.
    func testATrayThatIsLeavingIsNeverPutBack() {
        var machine = machine(edits: true)
        let leaving = machine.handle(.dismissed)
        XCTAssertGreaterThan(leaving.to.translation, 0)

        let afterKeyboard = machine.handle(.keyboardMeasured(0))
        XCTAssertGreaterThan(
            afterKeyboard.to.translation, 0,
            "the keyboard reporting in cannot put a leaving tray back"
        )
    }

    // Its exit was measured against a keyboard it had just sent away, so the card was told to travel
    // from a place it was no longer going to be.
    func testATrayLeavingBesideTheKeyboardIsMeasuredFromWhereItWillBe() {
        var machine = machine(edits: true)
        let leaving = machine.handle(.dismissed)
        XCTAssertEqual(leaving.to.bottomInset, trayBottomMargin, "measured with the keyboard gone")
    }

    // Two animations back to back is what a stall is. The keyboard says how long it takes and on what
    // curve before it moves, so the tray leaves on that same clock and there is no handoff at all.
    func testATrayLeavingBesideTheKeyboardBorrowsItsClock() {
        var machine = machine(edits: true)
        let timing = PinTrayMachine.KeyboardTiming(duration: 0.25, curve: 7)
        machine.keyboardTiming = timing
        XCTAssertEqual(machine.handle(.dismissed).timeline, .matching(timing))
    }

    func testATrayLeavingWithNoKeyboardUsesOurOwnSpring() {
        var machine = machine()
        machine.keyboardTiming = PinTrayMachine.KeyboardTiming(duration: 0.25, curve: 7)
        XCTAssertEqual(machine.handle(.dismissed).timeline, .spring(bounce: 0))
    }

    func testDismissingWhileEditingTakesTheKeyboardWithIt() {
        var machine = machine(edits: true)
        let gone = machine.handle(.dismissed)
        XCTAssertEqual(gone.effects, [.dismissKeyboard])
        XCTAssertTrue(gone.dismisses)
    }
}
