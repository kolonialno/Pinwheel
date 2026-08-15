import SwiftUI

/// A row that shows what is currently chosen and opens the tray that changes it.
public struct PinTrayValue: SwiftUI.View {
    private let label: String
    private let value: String
    private let open: () -> Void

    public init(_ label: String, value: String, open: @escaping () -> Void) {
        self.label = label
        self.value = value
        self.open = open
    }

    public var body: some SwiftUI.View {
        SwiftUI.Button(action: open) {
            HStack(spacing: .spacingS) {
                PinLabel(label)
                Spacer(minLength: .spacingL)
                PinLabel(value).color(.secondary)
                Image(systemName: "chevron.forward")
                    .imageScale(.small)
                    .foregroundStyle(.tertiaryText)
            }
            .frame(minHeight: .minimumControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .spacingXL)
        .accessibilityIdentifier("pinwheel.tray.value.\(label)")
    }
}
