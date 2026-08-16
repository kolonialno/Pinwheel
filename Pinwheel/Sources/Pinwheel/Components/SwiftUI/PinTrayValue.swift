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
                PinLabel(label).color(.secondary)
                Spacer(minLength: .spacingL)
                PinLabel(value).font(.bodySemibold)
                Image(systemName: "chevron.forward")
                    .imageScale(.small)
                    .foregroundStyle(.secondaryText)
            }
            .padding(.horizontal, .spacingL)
            .frame(minHeight: .minimumControlHeight)
            .background(RoundedRectangle(cornerRadius: .radiusM).fill(Color.secondaryBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pinwheel.tray.value.\(label)")
    }
}
