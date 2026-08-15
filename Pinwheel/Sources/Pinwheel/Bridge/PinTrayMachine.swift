import CoreGraphics
import Foundation

/// Measured off the reference: a settle of about a third of a second with a barely-there overshoot,
/// its duration scaling with distance, which is a spring rather than a timed curve.
let trayResizeDuration: TimeInterval = 0.30
let trayResizeBounce: CGFloat = 0.10
let trayDismissVelocity: CGFloat = 800

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

    enum Phase: Equatable {
        /// Standing, or on its way there.
        case standing
        /// A tray that will raise the keyboard has moved in, and is holding still until it does.
        case awaitingKeyboard
        case leaving
    }

    /// Who moves the tray. A change may only ever belong to one of them.
    enum Timeline: Equatable {
        /// Applied with no animation at all — an entry position, or a drag tracking a finger.
        case immediate
        /// Ours, for a change nothing else owns.
        case spring(bounce: CGFloat)
        /// The keyboard's. We set the value and let its animation carry it.
        case carriedByKeyboard
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
        case contentResized(CGFloat)
        case keyboardMeasured(CGFloat)
        case dragged(CGFloat)
        case released(velocity: CGFloat, dismissBeyond: CGFloat)
        case dismissed
    }

    /// What the views should do: place `from` at once if given, then travel to `to` on `timeline`.
    struct Reaction: Equatable {
        var from: PinTrayGeometry?
        var to: PinTrayGeometry
        var timeline: Timeline
        var effects: [Effect] = []
        var dismisses = false
    }

    private(set) var phase: Phase = .standing
    private(set) var keyboard: Keyboard = .closed
    private(set) var contentHeight: CGFloat = 0
    /// A tray waiting for the keyboard keeps the height it is standing at until the keyboard moves.
    /// Adopting the new one first is the dip: a shorter card with no keyboard under it yet sits on the
    /// floor, so the top falls there and has to climb back.
    private var pendingContentHeight: CGFloat?
    /// Whether the standing tray is one that raises the keyboard, and so must let it lead.
    private(set) var edits = false
    private(set) var dragOffset: CGFloat = 0
    var room: PinTrayGeometry.Room

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

    mutating func handle(_ event: Event) -> Reaction {
        switch event {
        case .presented(let height):
            contentHeight = height
            phase = .standing
            return Reaction(from: geometry(.arriving), to: geometry(.resting), timeline: .spring(bounce: trayResizeBounce))

        case .moved(let height, let edits, let isPush):
            let wasEditing = self.edits
            let wasStanding = contentHeight
            contentHeight = height
            pendingContentHeight = nil
            self.edits = edits
            // A tray about to raise the keyboard holds still until it does: shrinking with no keyboard
            // under it sends the top down to the floor and back up again.
            if isPush, edits, keyboard == .closed {
                contentHeight = wasStanding
                pendingContentHeight = height
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
            let waited = phase == .awaitingKeyboard
            if waited {
                phase = .standing
                pendingContentHeight.map { contentHeight = $0 }
                pendingContentHeight = nil
            }
            // Whenever the keyboard is moving it owns the timeline, whether the tray was waiting for
            // it or is simply standing in its way.
            return Reaction(
                to: geometry(.resting),
                timeline: keyboard.ownsTheTimeline || waited ? .carriedByKeyboard : .spring(bounce: 0)
            )

        case .contentResized(let height):
            contentHeight = height
            // Content settling is not navigation: it resizes and nothing else, and an overshoot here
            // reverses direction under someone who is reading.
            return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0))

        case .dragged(let offset):
            dragOffset = max(0, offset)
            return Reaction(to: geometry(.resting), timeline: .immediate)

        case .released(let velocity, let dismissBeyond):
            let travelled = dragOffset
            dragOffset = 0
            guard velocity > trayDismissVelocity || travelled > dismissBeyond else {
                return Reaction(to: geometry(.resting), timeline: .spring(bounce: trayResizeBounce))
            }
            phase = .leaving
            return Reaction(to: geometry(.leaving), timeline: .spring(bounce: 0), dismisses: true)

        case .dismissed:
            phase = .leaving
            let effects: [Effect] = keyboard == .closed ? [] : [.dismissKeyboard]
            return Reaction(to: geometry(.leaving), timeline: .spring(bounce: 0), effects: effects, dismisses: true)
        }
    }
}
