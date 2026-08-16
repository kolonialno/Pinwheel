import SwiftUI

/// One of a set of mutually exclusive options. Choosing applies at once — a tray of choices has nothing
/// to commit, so it has no commit button and closing it is not an undo.
///
/// A list marks its choice with a tick rather than a fill. A wheel can mark one by where it sits, and
/// does; a list has no position to read, and a soft fill is not enough on its own (WCAG 1.4.1, 1.4.11).
public struct PinTrayChoice: SwiftUI.View {
    private let label: String
    private let systemImage: String?
    private let isChosen: Bool
    private let choose: () -> Void

    public init(
        _ label: String,
        systemImage: String? = nil,
        isChosen: Bool,
        choose: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.isChosen = isChosen
        self.choose = choose
    }

    public var body: some SwiftUI.View {
        SwiftUI.Button(action: choose) {
            HStack(spacing: .spacingM) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.primaryText)
                        // A fixed width, so every label starts at the same place whatever its icon.
                        .frame(width: .spacingXXL, alignment: .center)
                }
                PinLabel(label)
                Spacer(minLength: .spacingL)
                Image(systemName: "checkmark")
                    .foregroundStyle(.primaryText)
                    .opacity(isChosen ? 1 : 0)
            }
            .padding(.horizontal, .spacingL)
            .frame(minHeight: .minimumControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
        .accessibilityIdentifier("pinwheel.tray.choice.\(label)")
    }
}
