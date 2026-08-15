import SwiftUI

/// One of a set of mutually exclusive options. Choosing applies at once — a tray of choices has nothing
/// to commit, so it has no commit button and closing it is not an undo.
public struct PinTrayChoice: SwiftUI.View {
    private let label: String
    private let detail: String?
    private let isChosen: Bool
    private let choose: () -> Void

    public init(_ label: String, detail: String? = nil, isChosen: Bool, choose: @escaping () -> Void) {
        self.label = label
        self.detail = detail
        self.isChosen = isChosen
        self.choose = choose
    }

    public var body: some SwiftUI.View {
        SwiftUI.Button(action: choose) {
            HStack(spacing: .spacingS) {
                PinLabel(label)
                Spacer(minLength: .spacingL)
                if let detail {
                    PinLabel(detail).color(.secondary)
                }
                Image(systemName: "checkmark")
                    .imageScale(.small)
                    .foregroundStyle(.primaryText)
                    .opacity(isChosen ? 1 : 0)
            }
            .frame(minHeight: .minimumControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .spacingXL)
        .accessibilityIdentifier("pinwheel.tray.choice.\(label)")
    }
}
