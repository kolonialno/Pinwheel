import SwiftUI
import UIKit

/// What stands at the bottom of the card: a tray's floating content, or the button that ends the flow.
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

    func show(_ leaf: AnyView?, isCommitButton: Bool, replacing: Bool, over duration: TimeInterval) {
        let leaving = standing
        guard let leaf else {
            standing = nil
            fade(leaving?.view, to: 0, animated: replacing, over: duration) { $0.detach() }
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

        let holds = replacing && leaving?.isCommitButton == true && isCommitButton
        arriving.alpha = holds || !replacing ? 1 : 0
        if holds, let leaving { bringSubviewToFront(leaving.view) }

        standing = (arriving, isCommitButton)
        invalidateIntrinsicContentSize()

        guard replacing else {
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
