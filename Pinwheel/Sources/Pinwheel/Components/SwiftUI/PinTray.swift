import SwiftUI

extension EnvironmentValues {
    @Entry var pinTrayDepth: Int = 0
    @Entry var pinTrayExit: () -> Void = {}
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
