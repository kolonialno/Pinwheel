import UIKit

@MainActor
final class PinTrayCardView: UIView {
    let surface = UIView()

    weak var reporting: PinTrayCardReporting?

    private var height = NSLayoutConstraint()
    private var offset = NSLayoutConstraint()
    private var motion: UIViewPropertyAnimator?

    init(nestedIn displayCornerRadius: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = displayCornerRadius
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.cornerCurve = .continuous
        clipsToBounds = true

        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.backgroundColor = .primaryBackground
        surface.layer.cornerRadius = trayTopRadius
        surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        surface.layer.cornerCurve = .continuous
        surface.clipsToBounds = true
        addSubview(surface)

        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func attach(to parent: UIView) {
        parent.addSubview(self)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag))
        pan.delegate = self
        addGestureRecognizer(pan)
        parent.keyboardLayoutGuide.usesBottomSafeArea = false
        height = heightAnchor.constraint(equalToConstant: 0)
        height.priority = .defaultHigh
        offset = bottomAnchor.constraint(
            equalTo: parent.keyboardLayoutGuide.topAnchor,
            constant: -trayBottomMargin
        )
        let lifted = bottomAnchor.constraint(
            equalTo: parent.keyboardLayoutGuide.topAnchor,
            constant: -trayKeyboardMargin
        )
        offset.priority = UILayoutPriority(999)
        lifted.priority = UILayoutPriority(999)
        parent.keyboardLayoutGuide.setConstraints([offset], activeWhenNearEdge: .bottom)
        parent.keyboardLayoutGuide.setConstraints([lifted], activeWhenAwayFrom: .bottom)

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: trayMargin),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -trayMargin),
            topAnchor.constraint(
                greaterThanOrEqualTo: parent.safeAreaLayoutGuide.topAnchor,
                constant: trayMargin
            ),
            height,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PinTrayCardView is made in code") }

    func writeConstants(from geometry: PinTrayGeometry) {
        layer.cornerRadius = geometry.bottomCornerRadius
        height.constant = geometry.height
        offset.constant = -geometry.clearanceAboveGuide
    }

    var travelled: CGFloat { transform.ty }

    var isTravelling: Bool { motion?.isRunning == true }

    func stopTravelling() {
        motion?.stopAnimation(true)
        motion = nil
    }

    func place(
        _ geometry: PinTrayGeometry,
        alongside: @escaping () -> Void,
        matching timing: PinTrayMachine.KeyboardTiming,
        then finish: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: timing.duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: UInt(timing.curve) << 16),
            animations: {
                self.draw(geometry)
                alongside()
            },
            completion: { _ in finish() }
        )
    }

    func place(
        _ geometry: PinTrayGeometry,
        alongside: @escaping () -> Void,
        animated: Bool,
        bounce: CGFloat = trayResizeBounce,
        startingAt initialVelocity: CGFloat = 0,
        then finish: @escaping () -> Void = {}
    ) {
        let draw = {
            self.draw(geometry)
            alongside()
        }
        stopTravelling()
        guard animated else { draw(); return finish() }
        let animator = UIViewPropertyAnimator(
            duration: trayResizeDuration,
            timingParameters: UISpringTimingParameters(
                duration: trayResizeDuration,
                bounce: bounce,
                initialVelocity: CGVector(dx: 0, dy: initialVelocity)
            )
        )
        animator.addAnimations(draw)
        animator.addCompletion { position in
            guard position == .end else { return }
            finish()
        }
        motion = animator
        animator.startAnimation()
    }

    private func draw(_ geometry: PinTrayGeometry) {
        writeConstants(from: geometry)
        transform = CGAffineTransform(translationX: 0, y: geometry.translation)
        superview?.layoutIfNeeded()
    }
}

extension PinTrayCardView {
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let travelled = gesture.translation(in: superview).y
        switch gesture.state {
        case .began:
            if isTravelling { reporting?.cardWasCaught(at: self.travelled) }
            gesture.setTranslation(
                CGPoint(x: 0, y: reporting?.pulledSoFar ?? 0),
                in: superview
            )
        case .changed:
            reporting?.cardWasDragged(to: travelled)
        case .ended, .cancelled:
            reporting?.cardWasReleased(velocity: gesture.velocity(in: superview).y)
        default:
            break
        }
    }
}

extension PinTrayCardView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let candidate = view, candidate !== self {
            if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled { return false }
            view = candidate.superview
        }
        return true
    }
}
