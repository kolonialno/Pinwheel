import SwiftUI

extension EnvironmentValues {
    @Entry var pinTrayDepth: Int = 0
    @Entry var pinTrayExit: () -> Void = {}
    @Entry var pinTrayPhase: PinTrayPhase? = nil
    @Entry var pinTrayBottomInset: CGFloat = .spacingL
    @Entry var pinTrayMediumHeight: CGFloat = 0
}

/// The zoom a tray's content carries through a transition. It rides the content alone — a title that
/// grew on its way out would read as the tray moving, where the reference keeps its chrome still and
/// lets only the content travel.
@Observable
final class PinTrayPhase {
    var contentZoom: CGFloat = 1
}

public struct PinTray<Content: SwiftUI.View, Accessory: SwiftUI.View>: SwiftUI.View {
    /// How tall a tray stands. `.fitting` is the rule — as tall as what it holds. `.medium` is for a
    /// surface you browse rather than read: it takes a standing height and scrolls inside it, so a
    /// list that filters as you type does not move the tray on every keystroke.
    public enum Detent {
        case fitting
        case medium
    }

    private struct Commit {
        let title: String
        let action: () -> Void
    }

    private let title: String
    private let content: () -> Content
    private let accessory: () -> Accessory
    private var commit: Commit?
    private var detent: Detent = .fitting

    @Environment(\.pinwheelTheme) private var theme
    @Environment(\.pinTrayDepth) private var depth
    @Environment(\.pinTrayExit) private var exit
    @Environment(\.pinTrayPhase) private var phase
    @Environment(\.pinTrayBottomInset) private var bottomInset
    @Environment(\.pinTrayMediumHeight) private var mediumHeight

    public init(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.content = content
        self.accessory = accessory
    }

    public func detent(_ detent: Detent) -> PinTray {
        var copy = self
        copy.detent = detent
        return copy
    }

    public func commit(_ title: String, action: @escaping () -> Void) -> PinTray {
        var copy = self
        copy.commit = Commit(title: title, action: action)
        return copy
    }

    public var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .frame(height: 1)
                .overlay(Color.tertiaryText)
                .padding(.horizontal, .spacingXL)
            content()
                .scaleEffect(phase?.contentZoom ?? 1)
            if let commit {
                PinButton(commit.title, action: commit.action)
                    .style(.custom(text: .primaryBackground, background: .primaryText))
                    .fullWidth()
                    .padding(.horizontal, .spacingXL)
                    .padding(.top, .spacingXL)
            }
        }
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .frame(height: standingHeight, alignment: .top)
    }

    private var standingHeight: CGFloat? {
        detent == .medium && mediumHeight > 0 ? mediumHeight : nil
    }

    private var isRoot: Bool { depth == 0 }

    private var header: some SwiftUI.View {
        ZStack {
            PinLabel(title)
                .font(.subtitleSemibold)
                .accessibilityIdentifier("pinwheel.tray.\(title).theme.\(theme.name)")
            HStack {
                SwiftUI.Button(action: exit) {
                    Image(systemName: isRoot ? "xmark" : "chevron.backward")
                        .font(PinTextStyle.body.font(in: theme))
                        .symbolRenderingMode(.monochrome)
                        .imageScale(.large)
                }
                .tint(.primaryText)
                .accessibilityLabel(isRoot ? "Close" : "Back")
                Spacer()
                accessory()
                    .tint(.primaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: .minimumControlHeight)
        .padding(.horizontal, .spacingXL)
        .padding(.vertical, .spacingS)
    }
}

extension PinTray where Accessory == EmptyView {
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, content: content, accessory: { EmptyView() })
    }
}

public extension Animation {
    /// Content changing inside a standing tray, which resizes it — the same spring the tray moves on.
    static let trayContent = Animation.spring(duration: 0.30, bounce: 0.10)
}
