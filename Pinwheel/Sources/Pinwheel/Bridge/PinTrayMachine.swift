import CoreGraphics
import Foundation

/// Measured off the reference: a settle of about a third of a second with a barely-there overshoot,
/// its duration scaling with distance, which is a spring rather than a timed curve.
let trayResizeDuration: TimeInterval = 0.30
let trayResizeBounce: CGFloat = 0.10

/// The tray as a machine. Every rule learned by filming the reference lives here as state, including
/// the one that is easiest to get wrong: *which animation owns a change*.
///
/// The keyboard is not ours to command, so it enters as reports from an independent actor rather than
/// as something we set. That distinction is the whole design: a change the keyboard owns must be
/// carried by the keyboard's animation, and starting our own beside it is what reads as two steps.
struct PinTrayMachine: Equatable {
    /// What the keyboard is doing, as reported. `opening`/`closing` are the states in which it owns
    /// the timeline; nothing of ours may animate against it while it does.
    enum Keyboard: Equatable {
        case closed
        case opening(height: CGFloat)
        case open(height: CGFloat)
        case closing

        var height: CGFloat {
            switch self {
            case .closed, .closing: return 0
            case .opening(let height), .open(let height): return height
            }
        }

        var ownsTheTimeline: Bool {
            switch self {
            case .opening, .closing: return true
            case .closed, .open: return false
            }
        }
    }

    /// Where the tray is in its life. One axis, so a tray cannot be leaving and arriving at once, and
    /// "is a move still resolving" is a question about this rather than a second flag beside it.
    enum Phase: Equatable {
        /// A move has started and has not resolved: what the arriving tray says about itself lands in
        /// this window, and is recorded rather than drawn.
        case arriving
        /// Moved in, and holding still until the keyboard it will raise actually moves.
        case awaitingKeyboard
        case standing
        case leaving

        /// Whether a move is still resolving.
        var isResolvingAMove: Bool {
            switch self {
            case .arriving, .awaitingKeyboard: return true
            case .standing, .leaving: return false
            }
        }
    }

    /// How the keyboard moves, which it announces before moving. Borrowing these is what lets a tray
    /// leave beside it on one curve instead of handing off to a second animation.
    /// What an arriving tray says about itself before the move that describes it resolves.
    struct Arriving: Equatable {
        var contentHeight: CGFloat
        var fills: Bool
    }

    struct KeyboardTiming: Equatable {
        var duration: TimeInterval
        var curve: Int
    }

    /// Who moves the tray. A change may only ever belong to one of them.
    enum Timeline: Equatable {
        /// Applied with no animation at all — an entry position, or a drag tracking a finger.
        case immediate
        /// Ours, for a change nothing else owns.
        case spring(bounce: CGFloat)
        /// The keyboard's. We set the value and let its animation carry it.
        case carriedByKeyboard
        /// Ours, on the keyboard's own clock and curve — for a move that has to travel further than the
        /// keyboard does while still reading as the same motion.
        case matching(KeyboardTiming)
    }

    /// Something only the outside world can do.
    enum Effect: Equatable {
        /// A tray being left must dismiss the keyboard deliberately: unmounting it tears the field
        /// out from under the keyboard, which then leaves with no animation to travel with.
        case dismissKeyboard
    }

    enum Event: Equatable {
        case presented(contentHeight: CGFloat)
        case moved(contentHeight: CGFloat, edits: Bool, isPush: Bool)
        /// A move has started. Sent the moment it does, because what the arriving tray says about
        /// itself lands before the move that describes it resolves.
        case moveBegan(isPush: Bool)
        /// The tray saying how it stands. It arrives from SwiftUI whenever SwiftUI gets round to it.
        case fillsReported(Bool)
        case contentResized(CGFloat)
        case keyboardMeasured(CGFloat)
        case dragged(CGFloat)
        case released(velocity: CGFloat, dismissBeyond: CGFloat)
        case dismissed
        /// The room changed under it — rotation, a split view, a resized container.
        case roomChanged(PinTrayGeometry.Room)
    }

    /// What the views should do: place `from` at once if given, then travel to `to` on `timeline`.
    struct Reaction: Equatable {
        var from: PinTrayGeometry?
        var to: PinTrayGeometry
        var timeline: Timeline
        /// The speed a finger let go at, in points a second. A motion that carries on from a hand has
        /// to leave at the speed the hand left it, or it reads as a second motion.
        var velocity: CGFloat = 0
        var effects: [Effect] = []
        var dismisses = false
    }

    private(set) var phase: Phase = .standing
    private(set) var keyboard: Keyboard = .closed
    private(set) var contentHeight: CGFloat = 0
    /// Whether the standing tray takes all the room there is rather than the height of what it holds.
    private(set) var fills = false
    /// A tray waiting for the keyboard keeps the height it is standing at until the keyboard moves.
    /// Adopting the new one first is the dip: a shorter card with no keyboard under it yet sits on the
    /// floor, so the top falls there and has to climb back.
    /// What the arriving tray said about itself while the move was still resolving. One value, adopted
    /// in one place: it grew a second field once and every branch that adopts had to be found again.
    private var arriving: Arriving?
    /// Whether the standing tray is one that raises the keyboard, and so must let it lead.
    private(set) var edits = false
    private(set) var dragOffset: CGFloat = 0
    private(set) var room: PinTrayGeometry.Room
    /// What the keyboard last said about how it moves. Not an event: it changes how a move is drawn,
    /// never where it goes.
    var keyboardTiming: KeyboardTiming?

    init(room: PinTrayGeometry.Room) {
        self.room = room
    }

    /// What a measured height means, read against what the keyboard was last doing. Moving or settled
    /// is a conclusion rather than an observation, so it is drawn here — anywhere else is a second copy
    /// of the keyboard's state, and the two go out of step the moment we ask it to leave.
    func keyboard(measuring height: CGFloat) -> Keyboard {
        let previous = keyboard.height
        guard height > 0 else { return previous > 0 ? .closing : .closed }
        return height == previous ? .open(height: height) : .opening(height: height)
    }

    private func geometry(_ phase: PinTrayGeometry.Phase) -> PinTrayGeometry {
        PinTrayGeometry(
            contentHeight: contentHeight,
            fills: fills,
            room: room,
            keyboardInset: keyboard.height,
            dragOffset: dragOffset,
            phase: phase,
            standsOnKeyboard: edits
        )
    }

    var geometry: PinTrayGeometry {
        geometry(phase == .leaving ? .leaving : .resting)
    }

    /// What SwiftUI hands over about the tray that is arriving: how it stands, and how tall its content
    /// measures. Mid-move these are news rather than instructions — the tray on screen is still the
    /// outgoing one, so drawing them puts the arriving tray's shape in the outgoing tray's place. That
    /// collapse, measured, was 641 to 245 and back up to 828 on every push.
    private mutating func recordForTheArrivingTray(_ event: Event) -> Bool {
        switch event {
        case .fillsReported(let fills):
            arriving = Arriving(contentHeight: arriving?.contentHeight ?? contentHeight, fills: fills)
            return true
        case .contentResized(let height):
            arriving = Arriving(contentHeight: height, fills: arriving?.fills ?? fills)
            return true
        default:
            return false
        }
    }

    /// Takes up whatever the arriving tray said about itself. Every branch that finishes a move calls
    /// this and nothing else, so a new thing an arriving tray can say is added in one place.
    private mutating func adoptWhatArrived() {
        guard let arriving else { return }
        contentHeight = arriving.contentHeight
        fills = arriving.fills
        self.arriving = nil
    }

    mutating func handle(_ event: Event) -> Reaction {
        let drawn = geometry
        var reaction = resolve(event)
        // A reaction that changes nothing starts nothing. Dragging the list to put the keyboard away,
        // every sample arrived twice — moving, then apparently settled — and the settled one started a
        // spring against a keyboard still under the finger, sixty times a second. An interactive
        // dismissal never really settles, so the honest test is whether anything actually moved.
        if reaction.from == nil, reaction.effects.isEmpty, !reaction.dismisses, reaction.to == drawn {
            reaction.timeline = .carriedByKeyboard
        }
        return reaction
    }

    private mutating func resolve(_ event: Event) -> Reaction {
        if phase.isResolvingAMove, recordForTheArrivingTray(event) {
            return Reaction(to: geometry(.resting), timeline: .carriedByKeyboard)
        }
        switch event {
        case .presented(let height):
            arriving = Arriving(contentHeight: height, fills: arriving?.fills ?? fills)
            adoptWhatArrived()
            phase = .standing
            return Reaction(from: geometry(.arriving), to: geometry(.resting), timeline: .spring(bounce: trayResizeBounce))

        case .moved(let height, let edits, let isPush):
            let wasEditing = self.edits
            let wasStanding = contentHeight
            let wasFilling = fills
            let arrivingFills = arriving?.fills ?? fills
            contentHeight = height
            fills = arrivingFills
            arriving = nil
            self.edits = edits
            // A tray about to raise the keyboard holds still until it does: shrinking with no keyboard
            // under it sends the top down to the floor and back up again. A filling tray is sized by the
            // room rather than by what it holds, so its top is the same before and after the keyboard
            // arrives — there is no dip available to it and nothing to wait for.
            if isPush, edits, !arrivingFills, keyboard == .closed {
                contentHeight = wasStanding
                fills = wasFilling
                arriving = Arriving(contentHeight: height, fills: arrivingFills)
                phase = .awaitingKeyboard
                return Reaction(to: geometry(.resting), timeline: .carriedByKeyboard)
            }
            phase = .standing
            // Leaving a tray that was editing, the keyboard has to be told to go, or it is torn away
            // without an animation for the tray to travel beside.
            let dismissesKeyboard = !isPush && wasEditing && keyboard != .closed
            if dismissesKeyboard {
                // Commanding it away is a change to what the machine knows, taking effect now rather
                // than when the keyboard gets around to saying so. Dismissing re-lays the whole screen
                // at once, so the reports it provokes arrive *before* this reaction is drawn — and a
                // target computed against a keyboard we have already sent away would land on top of
                // them, leaving the tray at a height belonging to neither state.
                keyboard = .closing
                self.edits = false
            }
            return Reaction(
                to: geometry(.resting),
                timeline: .spring(bounce: trayResizeBounce),
                effects: dismissesKeyboard ? [.dismissKeyboard] : []
            )

        case .keyboardMeasured(let height):
            keyboard = keyboard(measuring: height)
            // A tray on its way out stays on its way out. The keyboard leaves at the same moment, and
            // answering its report with a resting position is what cancelled the exit half way down.
            guard phase != .leaving else {
                return Reaction(to: geometry(.leaving), timeline: .carriedByKeyboard)
            }
            let waited = phase == .awaitingKeyboard
            if waited {
                phase = .standing
                adoptWhatArrived()
            }
            // Whenever the keyboard is moving it owns the timeline, whether the tray was waiting for
            // it or is simply standing in its way.
            return Reaction(
                to: geometry(.resting),
                timeline: keyboard.ownsTheTimeline || waited ? .carriedByKeyboard : .spring(bounce: 0)
            )

        case .roomChanged(let room):
            self.room = room
            return Reaction(to: geometry(phase == .leaving ? .leaving : .resting), timeline: .carriedByKeyboard)

        case .moveBegan:
            // A tray already on its way out is not arriving anywhere.
            guard phase != .leaving else { return Reaction(to: geometry(.leaving), timeline: .carriedByKeyboard) }
            phase = .arriving
            return Reaction(to: geometry(.resting), timeline: .carriedByKeyboard)

        case .fillsReported(let fills):
            // Standing still, it takes effect now: there may be no next event at all, since with a
            // hardware keyboard attached the software keyboard never speaks.
            self.fills = fills
            return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0))

        case .contentResized(let height):
            // A filling tray is sized by the room, so what it holds has nothing to say about it.
            guard !fills else { return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0)) }
            contentHeight = height
            // Content settling is not navigation: it resizes and nothing else, and an overshoot here
            // reverses direction under someone who is reading.
            return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0))

        case .dragged(let offset):
            dragOffset = PinTrayGeometry.travel(forDrag: offset)
            return Reaction(to: geometry(.resting), timeline: .immediate)

        case .released(let velocity, let dismissBeyond):
            let travelled = dragOffset
            dragOffset = 0
            let lands = travelled + PinTrayGeometry.coast(atSpeed: velocity)
            guard lands > dismissBeyond else {
                return Reaction(
                    to: geometry(.resting),
                    timeline: .spring(bounce: trayResizeBounce),
                    velocity: velocity
                )
            }
            phase = .leaving
            return Reaction(
                to: geometry(.leaving),
                timeline: .spring(bounce: 0),
                velocity: velocity,
                dismisses: true
            )

        case .dismissed:
            phase = .leaving
            let takesTheKeyboardWithIt = keyboard != .closed
            if takesTheKeyboardWithIt {
                // Same rule as leaving a tray: ordered away counts as gone, so the exit is measured
                // from where the card is going to be rather than from where the keyboard had it.
                keyboard = .closing
                edits = false
            }
            // Travelling further than the keyboard does, but starting together and on its curve, is one
            // motion. Our own spring after it would be a second one, and the seam between them is the
            // stall.
            let timeline: Timeline = takesTheKeyboardWithIt
                ? keyboardTiming.map(Timeline.matching) ?? .spring(bounce: 0)
                : .spring(bounce: 0)
            return Reaction(
                to: geometry(.leaving),
                timeline: timeline,
                effects: takesTheKeyboardWithIt ? [.dismissKeyboard] : [],
                dismisses: true
            )
        }
    }
}
