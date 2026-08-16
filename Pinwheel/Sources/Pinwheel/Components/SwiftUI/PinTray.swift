import SwiftUI

/// One screen of a tray flow: a title, a body, and optionally something floating over the body and a
/// button that ends the flow.
///
/// A tray does not draw itself. It is the description a caller writes, and the chassis assembles it —
/// title bar, body and accessory are containers the chassis holds, and what a caller supplies is the
/// content of each. That is why this is a value and not a `View`: a thing that contained would need
/// SwiftUI to lay out and route gestures for the tray, which is the job UIKit does here.
public struct PinTray {
    /// How tall a tray stands: as tall as what it holds, or as tall as the room there is.
    ///
    /// `.filling` is for a surface you browse rather than read. It is anchored by its top — so the top is
    /// a constant no keyboard can move — and only its bottom travels, riding the keyboard down and
    /// stopping at the floor. The room it gains becomes list to scroll, and a list that filters as you
    /// type never moves the tray.
    public enum Detent {
        case fitting
        case filling
    }

    struct Commit {
        let title: String
        let action: () -> Void
    }

    let title: String
    let content: AnyView
    private(set) var titleAccessory: AnyView?
    private(set) var floating: AnyView?
    private(set) var commit: Commit?
    private(set) var detent: Detent = .fitting

    /// The tray stacks what it is given, so its sections stand apart by one number decided here rather
    /// than by every caller remembering it.
    public init<Content: SwiftUI.View>(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = AnyView(VStack(spacing: traySectionGap) { content() })
    }

    public func detent(_ detent: Detent) -> PinTray {
        var copy = self
        copy.detent = detent
        return copy
    }

    /// A control at the trailing end of the title bar.
    public func titleAccessory<Accessory: SwiftUI.View>(@ViewBuilder _ accessory: () -> Accessory) -> PinTray {
        var copy = self
        copy.titleAccessory = AnyView(accessory())
        return copy
    }

    /// Something that stands over the body at the tray's bottom edge — a search field, a filter bar. The
    /// body scrolls beneath it and keeps enough room below its last row to be read past it.
    public func floating<Floating: SwiftUI.View>(@ViewBuilder _ floating: () -> Floating) -> PinTray {
        var copy = self
        copy.floating = AnyView(floating())
        return copy
    }

    /// The button that ends the flow. Only where a flow genuinely ends: a choice that applies as it is
    /// tapped has nothing to commit.
    public func commit(_ title: String, action: @escaping () -> Void) -> PinTray {
        var copy = self
        copy.commit = Commit(title: title, action: action)
        return copy
    }
}

public extension Animation {
    /// Content changing inside a standing tray, which resizes it — the same spring the tray moves on.
    static let trayContent = Animation.spring(duration: 0.30, bounce: 0.10)
}
