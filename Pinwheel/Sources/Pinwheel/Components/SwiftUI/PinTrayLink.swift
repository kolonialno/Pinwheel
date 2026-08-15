import SwiftUI

/// A line of text ending in a phrase that leaves the app.
///
/// A button, not a label: tapping it opens a web page, and something that navigates has to read and
/// behave as a control. "Get up to 3x more likes. Learn more" is this.
public struct PinTrayLink: SwiftUI.View {
    private let text: String
    private let phrase: String
    private let open: () -> Void

    public init(_ text: String, phrase: String, open: @escaping () -> Void) {
        self.text = text
        self.phrase = phrase
        self.open = open
    }

    public var body: some SwiftUI.View {
        SwiftUI.Button(action: open) {
            HStack(spacing: .spacingXS) {
                PinLabel(text).color(.secondary)
                PinLabel(phrase).color(.action)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .spacingXL)
        .padding(.vertical, .spacingS)
        .accessibilityIdentifier("pinwheel.tray.link.\(phrase)")
    }
}
