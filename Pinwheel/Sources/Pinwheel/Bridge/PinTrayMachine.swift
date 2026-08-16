import CoreGraphics
import Foundation

/// Measured off the reference: a settle of about a third of a second with a barely-there overshoot,
/// whose duration scales with distance, which is a spring rather than a timed curve.
let trayResizeDuration: TimeInterval = 0.30
let trayResizeBounce: CGFloat = 0.10

struct PinTrayMachine: Equatable {
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
        case arriving
        case awaitingKeyboard
        case standing
        case leaving

        var isResolvingAMove: Bool {
            switch self {
            case .arriving, .awaitingKeyboard: return true
            case .standing, .leaving: return false
            }
        }
    }

    struct Arriving: Equatable {
        var contentHeight: CGFloat
        var fills: Bool
    }

    struct KeyboardTiming: Equatable {
        var duration: TimeInterval
        var curve: Int
    }

    enum Timeline: Equatable {
        case immediate
        case spring(bounce: CGFloat)
        case carriedByKeyboard
        case matching(KeyboardTiming)
    }

    enum Effect: Equatable {
        case dismissKeyboard
    }

    enum Event: Equatable {
        case presented(contentHeight: CGFloat)
        case moved(contentHeight: CGFloat, edits: Bool, isPush: Bool)
        case moveBegan(isPush: Bool)
        case fillsReported(Bool)
        case contentResized(CGFloat)
        case keyboardMeasured(CGFloat)
        case dragged(CGFloat)
        case caught(at: CGFloat)
        case released(velocity: CGFloat)
        case dismissed
        case roomChanged(PinTrayGeometry.Room)
    }

    struct Reaction: Equatable {
        var from: PinTrayGeometry?
        var to: PinTrayGeometry
        var timeline: Timeline
        var velocity: CGFloat = 0
        var effects: [Effect] = []
        var dismisses = false
    }

    private(set) var phase: Phase = .standing
    private(set) var keyboard: Keyboard = .closed
    private(set) var contentHeight: CGFloat = 0
    private(set) var fills = false
    private var arriving: Arriving?
    private(set) var edits = false
    private(set) var dragOffset: CGFloat = 0
    private(set) var room: PinTrayGeometry.Room
    var keyboardTiming: KeyboardTiming?

    init(room: PinTrayGeometry.Room) {
        self.room = room
    }

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

    private mutating func adoptWhatArrived() {
        guard let arriving else { return }
        contentHeight = arriving.contentHeight
        fills = arriving.fills
        self.arriving = nil
    }

    mutating func handle(_ event: Event) -> Reaction {
        let drawn = geometry
        var reaction = resolve(event)
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
            if isPush, edits, !arrivingFills, keyboard == .closed {
                contentHeight = wasStanding
                fills = wasFilling
                arriving = Arriving(contentHeight: height, fills: arrivingFills)
                phase = .awaitingKeyboard
                return Reaction(to: geometry(.resting), timeline: .carriedByKeyboard)
            }
            phase = .standing
            let dismissesKeyboard = !isPush && wasEditing && keyboard != .closed
            if dismissesKeyboard {
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
            guard phase != .leaving else {
                return Reaction(to: geometry(.leaving), timeline: .carriedByKeyboard)
            }
            let waited = phase == .awaitingKeyboard
            if waited {
                phase = .standing
                adoptWhatArrived()
            }
            return Reaction(
                to: geometry(.resting),
                timeline: keyboard.ownsTheTimeline || waited ? .carriedByKeyboard : .spring(bounce: 0)
            )

        case .roomChanged(let room):
            self.room = room
            return Reaction(to: geometry(phase == .leaving ? .leaving : .resting), timeline: .carriedByKeyboard)

        case .moveBegan:
            guard phase != .leaving else { return Reaction(to: geometry(.leaving), timeline: .carriedByKeyboard) }
            phase = .arriving
            return Reaction(to: geometry(.resting), timeline: .carriedByKeyboard)

        case .fillsReported(let fills):
            // With a hardware keyboard attached the software keyboard never speaks, so there may be
            // no next event to carry this.
            self.fills = fills
            return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0))

        case .contentResized(let height):
            guard !fills else { return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0)) }
            contentHeight = height
            return Reaction(to: geometry(.resting), timeline: .spring(bounce: 0))

        case .dragged(let offset):
            dragOffset = PinTrayGeometry.travel(forDrag: offset)
            return Reaction(to: geometry(.resting), timeline: .immediate)

        case .caught(let translation):
            phase = .standing
            dragOffset = max(0, translation)
            return Reaction(to: geometry(.resting), timeline: .immediate)

        case .released(let velocity):
            let travelled = dragOffset
            dragOffset = 0
            let lands = travelled + PinTrayGeometry.coast(atSpeed: velocity)
            guard lands > geometry(.leaving).translation / 2 else {
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
                keyboard = .closing
                edits = false
            }
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
