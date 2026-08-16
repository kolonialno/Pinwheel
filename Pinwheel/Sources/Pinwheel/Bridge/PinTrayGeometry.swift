import CoreGraphics

let trayMargin: CGFloat = .spacingS
let trayBottomMargin: CGFloat = .spacingS
let trayKeyboardMargin: CGFloat = .spacingL
let trayTopRadius: CGFloat = 32
/// How far a tray's contents stand off its edges. The card decides this for everything it holds — a row
/// only decides what happens inside itself.
let trayContentMargin: CGFloat = .spacingXL
/// How far a pull that has nowhere to go can lift a tray, however hard it is pulled.
let trayLift: CGFloat = .spacingXXL
/// How much of a pull past the end survives as travel, at the start of it. A scroll view's own figure.
let trayRubberBanding: CGFloat = 0.55
/// What a let-go tray decelerates at, and the speed below which a release is a hand coming to rest
/// rather than a throw. Both are UIKit's own, read off `_UIHyperInteractor` — the object its sheets
/// hand a drag to. The rate is `UIScrollView`'s `.fast`.
let trayDecelerationRate: CGFloat = 0.99
let trayThrowSpeed: CGFloat = 250
/// The strip of backdrop left above every tray. Tapping it dismisses the tray, so it is a control and
/// takes a control's minimum height — a tray that grew over it left 8pt and swallowed the taps aimed
/// there, which took the only way out that isn't the header.
let trayBackdropReach: CGFloat = .minimumControlHeight

/// Where a tray stands, as a value. It holds every rule about height, clearance and corner, and knows
/// nothing about views — so each rule is a test rather than a screen recording.
struct PinTrayGeometry: Equatable {
    /// A tray is either on its way in, standing, or on its way out. Arriving and leaving are the same
    /// place — below its own bottom edge — which is why one value covers both.
    enum Phase: Equatable {
        case arriving
        case resting
        case leaving
    }

    struct Room: Equatable {
        var containerHeight: CGFloat
        var safeAreaTop: CGFloat
        var safeAreaBottom: CGFloat
        var displayCornerRadius: CGFloat

        init(
            containerHeight: CGFloat,
            safeAreaTop: CGFloat = 0,
            safeAreaBottom: CGFloat = 0,
            displayCornerRadius: CGFloat = .radiusL
        ) {
            self.containerHeight = containerHeight
            self.safeAreaTop = safeAreaTop
            self.safeAreaBottom = safeAreaBottom
            self.displayCornerRadius = displayCornerRadius
        }
    }

    /// How tall the tray stands: what it holds, until there is no more room for it.
    let height: CGFloat
    /// How far the tray's bottom sits above the container's bottom.
    let bottomInset: CGFloat
    /// Carried over the layout, so a gesture and an arrival never fight the constraints beneath them.
    let translation: CGFloat
    /// What the content keeps clear below itself for the home indicator.
    let contentBottomInset: CGFloat
    /// A tray on the bottom edge is nested in the display's own corner and takes its radius.
    let bottomCornerRadius: CGFloat

    init(
        contentHeight: CGFloat,
        fills: Bool = false,
        room: Room,
        keyboardInset: CGFloat = 0,
        dragOffset: CGFloat = 0,
        phase: Phase = .resting,
        standsOnKeyboard: Bool = true
    ) {
        // A tray that is not editing rests at the bottom and lets the keyboard leave over it, so only
        // the keyboard moves. One that is editing stands on the keyboard, clearing it by more than it
        // clears the screen's own edge.
        // The bottom rides the keyboard down and stops at the floor, which the keyboard then carries
        // on past — so the clamp is what ends the tray's travel, not a second animation.
        let lifted = keyboardInset > 0 && standsOnKeyboard
        bottomInset = max(trayBottomMargin, lifted ? keyboardInset + trayKeyboardMargin : 0)
        bottomCornerRadius = lifted ? trayTopRadius : room.displayCornerRadius

        // A filling tray is anchored by its top, which is therefore a constant no keyboard can move:
        // only the bottom travels, and the room it gains becomes list to scroll.
        let available = room.containerHeight - room.safeAreaTop - trayBackdropReach - bottomInset
        height = max(0, fills ? available : min(contentHeight, available))

        // The home indicator's strip, less the margin the tray already stands off the screen by.
        contentBottomInset = max(room.safeAreaBottom - trayBottomMargin, .spacingL)

        switch phase {
        case .arriving, .leaving:
            translation = height + bottomInset
        case .resting:
            translation = dragOffset
        }
    }
}

extension PinTrayGeometry {
    /// How far a tray travels for a finger that has come `offset` from where it began. Downward it
    /// follows exactly, because it is on its way out. Upward it has nowhere to go, so it resists.
    ///
    /// A scroll view would give the resistance for free, and gives none here: what has to move is the
    /// card rather than the list, and on a tray whose rows already fit there is no scrolling to bounce.
    ///
    /// This is Apple's own curve rather than something like it — `(x·d·c) / (d + c·x)`, checked against
    /// `-[UIScrollView _rubberBandOffsetForOffset:maxOffset:minOffset:range:outside:]` and equal to the
    /// penny at every pull, with `_currentRubberBandCoefficient` reading 0.55. Calling the private one
    /// would buy nothing and would put a private selector in every app that links this library.
    ///
    /// The one divergence is `d`. Apple passes the view's own dimension, which puts the limit out of
    /// reach; a tray passes `trayLift`, so however hard it is pulled it stops short and the strip above
    /// it that dismisses it stays tappable.
    static func travel(forDrag offset: CGFloat) -> CGFloat {
        guard offset < 0 else { return offset }
        let pulled = -offset * trayRubberBanding
        return -(pulled * trayLift / (trayLift + pulled))
    }
}

extension PinTrayGeometry {
    /// How much further a tray let go at this speed would coast before stopping. A sheet decides a
    /// dismiss on where a throw would land rather than on the speed it left at, which is why a gentle
    /// flick from nowhere goes and a fast jab that is already back at rest does not.
    static func coast(atSpeed velocity: CGFloat) -> CGFloat {
        guard abs(velocity) >= trayThrowSpeed else { return 0 }
        return velocity * trayDecelerationRate / (1 - trayDecelerationRate)
    }
}
