import SwiftUI
import UIKit

/// What stands at the bottom of the card: a tray's floating content, or the button that ends the flow.
///
/// It belongs to the card rather than to a tray, because a button that ends a flow outlives the tray it
/// was declared on. Where the tray arriving stands the same kind of thing, this holds what it has and
/// lets the one being left fade off it, so the pill never lightens. Where it stands something else, the
/// two cross-dissolve like everything else in a move.
@MainActor
final class PinTrayAccessoryView: UIView {
    private var standing: (view: PinTrayLeafView, isCommitButton: Bool)?
    private unowned let parent: UIViewController

    init(in parent: UIViewController) {
        self.parent = parent
        super.init(frame: .zero)
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PinTrayAccessoryView is made in code") }

    var height: CGFloat { standing?.view.height(fitting: bounds.width) ?? 0 }

    func height(fitting width: CGFloat) -> CGFloat {
        standing?.view.height(fitting: width) ?? 0
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    /// Puts `leaf` at the bottom of the card, taking whatever is already there off it.
    ///
    /// `animated` is false for a tray arriving on its own — there is nothing to fade against.
    func show(_ leaf: AnyView?, isCommitButton: Bool, animated: Bool, over duration: TimeInterval) {
        let leaving = standing
        guard let leaf else {
            standing = nil
            fade(leaving?.view, to: 0, animated: animated, over: duration) { $0.detach() }
            return
        }

        let arriving = PinTrayLeafView(showing: leaf, in: parent)
        arriving.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arriving)
        NSLayoutConstraint.activate([
            arriving.leadingAnchor.constraint(equalTo: leadingAnchor),
            arriving.trailingAnchor.constraint(equalTo: trailingAnchor),
            arriving.topAnchor.constraint(equalTo: topAnchor),
            arriving.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let holds = animated && leaving?.isCommitButton == true && isCommitButton
        arriving.alpha = holds || !animated ? 1 : 0
        if holds, let leaving { bringSubviewToFront(leaving.view) }

        standing = (arriving, isCommitButton)
        invalidateIntrinsicContentSize()

        guard animated else {
            leaving?.view.detach()
            leaving?.view.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: duration) {
            arriving.alpha = 1
            leaving?.view.alpha = 0
        } completion: { _ in
            leaving?.view.detach()
            leaving?.view.removeFromSuperview()
        }
    }

    private func fade(
        _ view: PinTrayLeafView?,
        to alpha: CGFloat,
        animated: Bool,
        over duration: TimeInterval,
        then finish: @escaping (PinTrayLeafView) -> Void
    ) {
        guard let view else { return }
        guard animated else { finish(view); view.removeFromSuperview(); return }
        UIView.animate(withDuration: duration) {
            view.alpha = alpha
        } completion: { _ in
            finish(view)
            view.removeFromSuperview()
        }
    }

    func detach() {
        standing?.view.detach()
        standing = nil
    }
}
