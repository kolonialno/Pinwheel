import CoreGraphics

let trayMargin: CGFloat = .spacingS
let trayBottomMargin: CGFloat = .spacingS
let trayKeyboardMargin: CGFloat = .spacingL
let trayTopRadius: CGFloat = 32

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
        room: Room,
        keyboardInset: CGFloat = 0,
        dragOffset: CGFloat = 0,
        phase: Phase = .resting,
        standsOnKeyboard: Bool = true
    ) {
        // A tray that is not editing rests at the bottom and lets the keyboard leave over it, so only
        // the keyboard moves. One that is editing stands on the keyboard, clearing it by more than it
        // clears the screen's own edge.
        let lifted = keyboardInset > 0 && standsOnKeyboard
        bottomInset = lifted ? keyboardInset + trayKeyboardMargin : trayBottomMargin
        bottomCornerRadius = lifted ? trayTopRadius : room.displayCornerRadius

        let available = room.containerHeight - room.safeAreaTop - trayMargin - bottomInset
        height = max(0, min(contentHeight, available))

        // The home indicator's strip, less the margin the tray already stands off the screen by.
        contentBottomInset = max(room.safeAreaBottom - trayBottomMargin, .spacingL)

        switch phase {
        case .arriving, .leaving:
            translation = height + bottomInset
        case .resting:
            translation = max(0, dragOffset)
        }
    }
}
