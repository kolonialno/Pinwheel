import SwiftUI

/// A titled group of rows. The tiers are one of these — a section of choices rather than a picker wheel,
/// which says the same thing, scrolls with everything else, and needs no component of its own.
public struct PinTraySection<Content: SwiftUI.View>: SwiftUI.View {
    private let title: String
    private let content: () -> Content

    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 0) {
            PinLabel(title)
                .font(.footnoteSemibold)
                .color(.secondary)
                .padding(.horizontal, .spacingXL)
                .padding(.top, .spacingL)
                .padding(.bottom, .spacingXS)
            content()
        }
    }
}
