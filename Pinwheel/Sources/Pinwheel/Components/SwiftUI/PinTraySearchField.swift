import SwiftUI

/// The field a search tray floats over its results. It takes focus as it appears, which is what raises
/// the keyboard the tray then stands on.
public struct PinTraySearchField: SwiftUI.View {
    private let prompt: String
    @SwiftUI.Binding private var text: String

    @Environment(\.pinwheelTheme) private var theme
    @FocusState private var focused: Bool

    public init(_ prompt: String, text: SwiftUI.Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    public var body: some SwiftUI.View {
        HStack(spacing: .spacingS) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondaryText)
            TextField(prompt, text: $text)
                .font(PinTextStyle.body.font(in: theme))
                .foregroundStyle(.primaryText)
                .focused($focused)
                .accessibilityIdentifier("pinwheel.tray.search")
        }
        .padding(.horizontal, .spacingL)
        .frame(minHeight: .minimumControlHeight)
        .background(
            RoundedRectangle(cornerRadius: .radiusL)
                .fill(Color.secondaryBackground)
        )
        .padding(.horizontal, .spacingXL)
        .onAppear { focused = true }
    }
}
