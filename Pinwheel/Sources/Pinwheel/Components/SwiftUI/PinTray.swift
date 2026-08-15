import SwiftUI

extension EnvironmentValues {
    @Entry var pinTrayDepth: Int = 0
    @Entry var pinTrayExit: () -> Void = {}
    @Entry var pinTrayPhase: PinTrayPhase? = nil
}

/// The zoom a tray's content carries through a transition. It rides the content alone — a title that
/// grew on its way out would read as the tray moving, where the reference keeps its chrome still and
/// lets only the content travel.
@Observable
final class PinTrayPhase {
    var contentZoom: CGFloat = 1
}

public struct PinTray<Content: SwiftUI.View, Accessory: SwiftUI.View>: SwiftUI.View {
    private struct Commit {
        let title: String
        let action: () -> Void
    }

    private let title: String
    private let content: () -> Content
    private let accessory: () -> Accessory
    private var commit: Commit?

    @Environment(\.pinwheelTheme) private var theme
    @Environment(\.pinTrayDepth) private var depth
    @Environment(\.pinTrayExit) private var exit
    @Environment(\.pinTrayPhase) private var phase

    public init(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.content = content
        self.accessory = accessory
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
        .padding(.bottom, .spacingXL)
        .frame(maxWidth: .infinity)
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
