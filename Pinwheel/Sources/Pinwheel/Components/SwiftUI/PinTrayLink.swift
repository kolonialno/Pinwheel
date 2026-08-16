import SwiftUI

/// A line of text ending in a phrase that leaves the app.
///
/// A button, not a label: tapping it opens a web page, and something that navigates has to read and
/// behave as a control. "Get up to 3x more likes. Learn more" is this, and so is the fine print above a
/// commit button.
///
/// The phrase is underlined rather than tinted. An accent colour on a sentence that is not the point of
/// the tray pulls the eye off what is, and an underline says the same thing quietly.
public struct PinTrayLink: SwiftUI.View {
    private let text: String
    private let phrase: String
    private let open: () -> Void
    private var style: PinTextStyle = .body

    @Environment(\.pinwheelTheme) private var theme

    public init(_ text: String, phrase: String, open: @escaping () -> Void) {
        self.text = text
        self.phrase = phrase
        self.open = open
    }

    public func font(_ font: PinTextStyle) -> PinTrayLink {
        var copy = self
        copy.style = font
        return copy
    }

    public var body: some SwiftUI.View {
        SwiftUI.Button(action: open) {
            // One `Text`, not an `HStack`: a sentence and its phrase have to wrap as one paragraph, and
            // a stack would lay them side by side and clip.
            (Text(text) + Text(" ") + Text(phrase).underline())
                .font(style.font(in: theme))
                .foregroundStyle(.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pinwheel.tray.link.\(phrase)")
    }
}
