import SwiftUI
import UIKit

/// A container for one SwiftUI leaf, sized by what the leaf draws.
///
/// The title bar and the floating accessory are both this: a `UIView` the chassis holds and lays out,
/// with SwiftUI inside it drawing and nothing else. Their heights are read from here rather than
/// measured through a preference, because the chassis needs them while it is laying out.
@MainActor
final class PinTrayLeafView: UIView {
    private let hosting: UIHostingController<AnyView>

    init(showing leaf: AnyView, in parent: UIViewController) {
        hosting = UIHostingController(rootView: leaf)
        super.init(frame: .zero)

        backgroundColor = .clear
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        parent.addChild(hosting)
        addSubview(hosting.view)
        hosting.didMove(toParent: parent)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PinTrayLeafView is made in code") }

    func show(_ leaf: AnyView) {
        hosting.rootView = leaf
    }

    /// How tall the leaf draws at this width.
    func height(fitting width: CGFloat) -> CGFloat {
        hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func detach() {
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }
}
