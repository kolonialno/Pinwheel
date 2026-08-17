import CoreGraphics

let trayMargin: CGFloat = .spacing2
let trayBottomMargin: CGFloat = .spacing2
let trayKeyboardMargin: CGFloat = .spacing4
let trayTopRadius: CGFloat = 32
let traySectionGap: CGFloat = .spacing5
let trayItemGap: CGFloat = .spacing3
let trayContentMargin: CGFloat = .spacing5
let trayLift: CGFloat = .spacing8
let trayRubberBanding: CGFloat = 0.55
/// Both are UIKit's own, read off the `_UIHyperInteractor` ivars its sheets hand a drag to. The rate
/// is `UIScrollView`'s `.fast`.
let trayDecelerationRate: CGFloat = 0.99
let trayThrowSpeed: CGFloat = 250
let trayBackdropReach: CGFloat = .minimumControlHeight

struct PinTrayGeometry: Equatable {
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

    let height: CGFloat
    let bottomInset: CGFloat
    let translation: CGFloat
    let contentBottomInset: CGFloat
    let bottomCornerRadius: CGFloat
    let dimming: CGFloat

    static func clearanceAboveAccessory(floats: Bool) -> CGFloat {
        floats ? .spacing2 : traySectionGap
    }

    init(
        contentHeight: CGFloat,
        fills: Bool = false,
        room: Room,
        keyboardInset: CGFloat = 0,
        dragOffset: CGFloat = 0,
        phase: Phase = .resting,
        standsOnKeyboard: Bool = true
    ) {
        let lifted = keyboardInset > 0 && standsOnKeyboard
        bottomInset = max(trayBottomMargin, lifted ? keyboardInset + trayKeyboardMargin : 0)
        bottomCornerRadius = lifted ? trayTopRadius : room.displayCornerRadius
        dimming = phase == .leaving ? 0 : 1

        let available = room.containerHeight - room.safeAreaTop - trayBackdropReach - bottomInset
        height = max(0, fills ? available : min(contentHeight, available))

        contentBottomInset = max(room.safeAreaBottom - trayBottomMargin, .spacing4)

        switch phase {
        case .arriving, .leaving:
            translation = height + bottomInset
        case .resting:
            translation = dragOffset
        }
    }
}

extension PinTrayGeometry {
    /// Apple's own curve, `(x·d·c) / (d + c·x)` — checked against
    /// `-[UIScrollView _rubberBandOffsetForOffset:maxOffset:minOffset:range:outside:]` and equal to the
    /// penny at every pull, with `_currentRubberBandCoefficient` reading 0.55. Calling the private one
    /// would put a private selector in every app that links this library. It diverges in `d` alone:
    /// Apple passes the view's own dimension, a tray passes `trayLift`.
    static func travel(forDrag offset: CGFloat) -> CGFloat {
        guard offset < 0 else { return offset }
        let pulled = -offset * trayRubberBanding
        return -(pulled * trayLift / (trayLift + pulled))
    }
}

extension PinTrayGeometry {
    static func coast(atSpeed velocity: CGFloat) -> CGFloat {
        guard abs(velocity) >= trayThrowSpeed else { return 0 }
        return velocity * trayDecelerationRate / (1 - trayDecelerationRate)
    }
}
