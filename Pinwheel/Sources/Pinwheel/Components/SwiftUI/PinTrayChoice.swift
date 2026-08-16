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
                PinLabel(label).color(isChosen ? .primary : .secondary)
                Spacer(minLength: .spacingL)
                if let detail {
                    PinLabel(detail)
                        .font(.titleSemibold)
                        .color(isChosen ? .primary : .secondary)
                }
            }
            .padding(.horizontal, .spacingL)
            .frame(minHeight: .minimumControlHeight)
            .background(
                RoundedRectangle(cornerRadius: .radiusM)
                    .fill(isChosen ? Color.secondaryBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .spacingXL)
        .padding(.vertical, .spacingXXS)
        // The fill is the only thing marking the choice on screen, so the trait is what carries it to
        // anyone who cannot see the fill.
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
        .accessibilityIdentifier("pinwheel.tray.choice.\(label)")
    }
}
