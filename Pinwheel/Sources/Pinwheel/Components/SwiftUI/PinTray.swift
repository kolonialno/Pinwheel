import SwiftUI

public struct PinTray {
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

    public init<Content: SwiftUI.View>(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = AnyView(VStack(spacing: traySectionGap) { content() })
    }

    public func detent(_ detent: Detent) -> PinTray {
        var copy = self
        copy.detent = detent
        return copy
    }

    public func titleAccessory<Accessory: SwiftUI.View>(@ViewBuilder _ accessory: () -> Accessory) -> PinTray {
        var copy = self
        copy.titleAccessory = AnyView(accessory())
        return copy
    }

    public func floating<Floating: SwiftUI.View>(@ViewBuilder _ floating: () -> Floating) -> PinTray {
        var copy = self
        copy.floating = AnyView(floating())
        return copy
    }

    public func commit(_ title: String, action: @escaping () -> Void) -> PinTray {
        var copy = self
        copy.commit = Commit(title: title, action: action)
        return copy
    }
}

public extension Animation {
    static let trayContent = Animation.spring(duration: 0.30, bounce: 0.10)
}
