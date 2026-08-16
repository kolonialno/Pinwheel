import SwiftUI

/// A run of items that belong together, which is the thing that owns the space between them.
///
/// It carries no title. A section is not a heading — it is the grouping itself, and a tray that wants a
/// heading writes one above the section.
public struct PinTraySection<Content: SwiftUI.View>: SwiftUI.View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some SwiftUI.View {
        VStack(spacing: trayItemGap) { content() }
    }
}
