import SwiftUI

/// The tray's title row, drawn: the way out on the leading edge, the title centred, an optional control
/// trailing. A leaf — it holds nothing and reports its taps to whoever handed it the closures.
struct PinTrayTitleBar: SwiftUI.View {
    let title: String
    let isRoot: Bool
    let accessory: AnyView?
    let exit: () -> Void

    @Environment(\.pinwheelTheme) private var theme

    var body: some SwiftUI.View {
        ZStack {
            PinLabel(title)
                .font(.subtitleSemibold)
                .accessibilityIdentifier("pinwheel.tray.\(title).theme.\(theme.name)")
            HStack {
                SwiftUI.Button(action: exit) {
                    Image(systemName: isRoot ? "xmark" : "chevron.backward")
                        .font(PinTextStyle.body.font(in: theme))
                        .symbolRenderingMode(.monochrome)
                        .imageScale(.medium)
                }
                .tint(.primaryText)
                .accessibilityLabel(isRoot ? "Close" : "Back")
                Spacer()
                // The bar sizes what it is handed, so both sides of it match whatever a caller passes.
                accessory
                    .font(PinTextStyle.body.font(in: theme))
                    .symbolRenderingMode(.monochrome)
                    .imageScale(.medium)
                    .tint(.primaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: .minimumControlHeight)
        .padding(.horizontal, .spacingXL)
        // The control keeps its floor; the band around it is what comes in. Both sides take the same
        // token, or the title sits off-centre in its own bar.
        .padding(.vertical, .spacingXM)
    }
}
