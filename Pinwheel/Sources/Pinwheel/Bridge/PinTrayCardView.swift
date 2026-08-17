import UIKit

/// The card a tray is drawn on. It stands where a geometry says, travels there on the timeline it is
/// given, and keeps the animation it is running so a finger landing on a moving card can take it over.
@MainActor
final class PinTrayCardView: UIView {
    /// What the card holds: a tray's contents, and whatever stands at its bottom.
    let surface = UIView()

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

    /// Joins the view it is drawn in, and takes its constraints from that view's guides. Separate from
    /// `init` because those guides belong to a view that cannot exist until this one does.
    func attach(to parent: UIView) {
        parent.addSubview(self)
        // The keyboard runs out of process and posts its notifications asynchronously, so anything
        // driven off them races its animation; a constraint to this guide is carried by that animation.
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
        // Toggling these by hand from layoutSubviews re-enters layout and UIKit throws.
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

    /// Everything about where the card stands, in one place — so a path that moves it cannot move it
    /// wearing the wrong corner.
    /// Where the card stands, written without laying out — for a move the keyboard's own animation
    /// carries. Laying out here re-enters layout, since that is where a keyboard is measured.
    func stands(at geometry: PinTrayGeometry) {
        layer.cornerRadius = geometry.bottomCornerRadius
        height.constant = geometry.height
        offset.constant = -geometry.clearanceAboveGuide
    }

    /// How far the card has travelled from where it stands.
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
        velocity: CGFloat = 0,
        then finish: @escaping () -> Void = {}
    ) {
        let travelling = geometry.translation - transform.ty
        let draw = {
            self.draw(geometry)
            alongside()
        }
        stopTravelling()
        guard animated else { draw(); return finish() }
        let velocityPerPointOfTravel = abs(travelling) > 1 ? velocity / travelling : 0
        let animator = UIViewPropertyAnimator(
            duration: trayResizeDuration,
            timingParameters: UISpringTimingParameters(
                duration: trayResizeDuration,
                bounce: bounce,
                initialVelocity: CGVector(dx: 0, dy: velocityPerPointOfTravel)
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
        stands(at: geometry)
        transform = CGAffineTransform(translationX: 0, y: geometry.translation)
        superview?.layoutIfNeeded()
    }
}
