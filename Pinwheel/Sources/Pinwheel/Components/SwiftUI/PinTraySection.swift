import SwiftUI

public struct PinTraySection<Content: SwiftUI.View>: SwiftUI.View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some SwiftUI.View {
        VStack(spacing: trayItemGap) { content() }
    }
}
