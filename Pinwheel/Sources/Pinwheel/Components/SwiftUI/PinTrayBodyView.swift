import SwiftUI
import UIKit

/// A tray's body: the content, and the only thing in a tray that scrolls.
///
/// It owns its scroll view and is that scroll view's delegate, which is the whole point. A pull past the
/// top is read from the scroll view's own gesture instead of being fought for with a second recogniser,
/// and the offset is held at the top so the list cannot rubber-band over nothing while the card moves.
@MainActor
final class PinTrayBodyView: UIView {
    private let scroll = UIScrollView()
    private let hosting: UIHostingController<AnyView>
    private var pulling = false
    /// How far past the top the finger has come in this gesture. The offset is pinned back to the top
    /// between frames, so each frame only knows its own slice of the journey.
    private var pulled: CGFloat = 0

    weak var coordinating: PinTrayBodyCoordinating?

    /// Room kept clear below the last row, so it can be read past whatever floats over the body.
    var clearance: CGFloat = 0 {
        didSet { scroll.contentInset.bottom = clearance }
    }

    init(showing content: AnyView, in parent: UIViewController) {
        hosting = UIHostingController(rootView: content)
        super.init(frame: .zero)

        scroll.backgroundColor = .clear
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.keyboardDismissMode = .interactive
        scroll.contentInset.top = .spacingL
        scroll.showsVerticalScrollIndicator = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        hosting.sizingOptions = .intrinsicContentSize
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        parent.addChild(hosting)
        scroll.addSubview(hosting.view)
        hosting.didMove(toParent: parent)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            hosting.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        scroll.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PinTrayBodyView is made in code") }

    func show(_ content: AnyView) {
        hosting.rootView = content
    }

    /// How tall the rows draw at this width, before any clearance. What a tray sized by its content is
    /// sized by.
    /// What the body needs to show everything at once: the rows, plus the room it keeps above and below
    /// them. Reporting the rows alone leaves the card short by those insets, and a tray sized to fit its
    /// content is then permanently scrollable by exactly that much.
    func contentHeight(fitting width: CGFloat) -> CGFloat {
        hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            + scroll.contentInset.top
            + scroll.contentInset.bottom
    }

    /// How much there is to scroll. Zero means the rows never sized, and nothing can be pulled past a
    /// top that is also the bottom.
    var scrollableHeight: CGFloat { scroll.contentSize.height }

    /// Whether there is more content than there is room to show it.
    var overflows: Bool {
        scroll.contentSize.height > scroll.bounds.height - scroll.contentInset.top - scroll.contentInset.bottom
    }

    /// Fades with the tray it belongs to.
    var fade: CGFloat {
        get { alpha }
        set { alpha = newValue }
    }

    func detach() {
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }
}

extension PinTrayBodyView {
    /// The finger has gone this far past the top since the last frame. Separate from the delegate so it
    /// can be driven directly: a scroll view will not pretend to be tracking for a test.
    func wasPulled(pastTheTop past: CGFloat) {
        pulling = true
        pulled += past
        coordinating?.bodyWasPulledDown(by: pulled)
    }
}

extension PinTrayBodyView {
    /// Whether the list is held at its top, having been taken `past` points beyond it. Held while it is
    /// being pulled down, because there is nothing above the first row and the pull belongs to whoever
    /// is coordinating, and held in both directions when the rows already fit, since there is nothing
    /// below the fold for a bounce to reveal. Separate from the delegate so it can be driven directly:
    /// a scroll view will not pretend to be tracking for a test.
    static func isHeld(at past: CGFloat, overflowing: Bool) -> Bool {
        past > 0 || !overflowing
    }
}

extension PinTrayBodyView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let past = -(scrollView.contentOffset.y + scrollView.contentInset.top)
        guard scrollView.isTracking, Self.isHeld(at: past, overflowing: overflows) else { return }
        scrollView.contentOffset.y = -scrollView.contentInset.top
        guard past > 0 else { return }
        wasPulled(pastTheTop: past)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pulled = 0
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard pulling else { return }
        pulling = false
        pulled = 0
        coordinating?.bodyStoppedBeingPulled(velocity: -velocity.y * 1_000)
    }
}
