import SwiftUI
import UIKit

private let trayDimming: CGFloat = 0.35

extension UIScreen {
    var pinDisplayCornerRadius: CGFloat {
        (value(forKey: "_displayCornerRadius") as? CGFloat) ?? .radiusL
    }
}

extension SwiftUI.View {
    public func pinwheelTray<Item: Hashable>(
        path: SwiftUI.Binding<[Item]>,
        content: @escaping (Item) -> PinTray
    ) -> some SwiftUI.View {
        background(PinTrayPresenter(path: path, content: content))
    }
}

private struct PinTrayPresenter<Item: Hashable>: UIViewControllerRepresentable {
    @SwiftUI.Binding var path: [Item]
    let content: (Item) -> PinTray

    func makeCoordinator() -> PinTrayCoordinator<Item> {
        PinTrayCoordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismissAll = { path.removeAll() }
        coordinator.exit = {
            if path.count <= 1 { path.removeAll() } else { path.removeLast() }
        }
        coordinator.sync(path: path, from: controller, tray: content)
    }
}

final class PinTrayCoordinator<Item: Hashable> {
    private var overlay: PinTrayOverlay?
    private var shown: [Item] = []

    var dismissAll: () -> Void = {}
    var exit: () -> Void = {}

    func sync(
        path: [Item],
        from presenter: UIViewController,
        tray: (Item) -> PinTray
    ) {
        guard path != shown else {
            if let top = path.last {
                overlay?.refresh(tray(top))
            }
            return
        }
        defer { shown = path }

        guard let top = path.last else {
            overlay?.dismiss()
            overlay = nil
            return
        }

        let description = tray(top)

        if let overlay {
            overlay.depth = path.count - 1
            overlay.show(description, isPush: path.count >= shown.count)
            return
        }

        guard var container = presenter.view.window?.rootViewController else { return }
        while let presented = container.presentedViewController { container = presented }

        let created = PinTrayOverlay(in: container, showing: description)
        created.depth = path.count - 1
        created.onBackgroundDismiss = { [weak self] in self?.dismissAll() }
        created.onExit = { [weak self] in self?.exit() }
        overlay = created
    }
}

final class PinTrayOverlay: UIView {
    private let dimming = UIView()
    private let tray = UIView()
    private let card = UIView()
    private var height = NSLayoutConstraint()
    private var offset = NSLayoutConstraint()
    private var rest = NSLayoutConstraint()
    private var displayRadius: CGFloat = .radiusL
    private lazy var machine = PinTrayMachine(room: room)

    private struct Standing {
        let description: PinTray
        let titleBar: PinTrayLeafView
        let body: PinTrayBodyView
        let accessory: PinTrayLeafView?
        let divider: UIView

        func detach() {
            titleBar.detach()
            body.detach()
            accessory?.detach()
            [titleBar, body, accessory, divider].compactMap { $0 }.forEach { $0.removeFromSuperview() }
        }

        var views: [UIView] { [titleBar, divider, body, accessory].compactMap { $0 } }

        var dissolving: [UIView] { [titleBar, divider, body] }

        var commitButton: PinTrayLeafView? {
            description.standsACommitButton ? accessory : nil
        }
    }

    private var standing: Standing?

    private unowned let container: UIViewController
    init(in container: UIViewController, showing tray: PinTray) {
        self.container = container
        super.init(frame: container.view.bounds)
        build()
        present(tray)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PinTrayOverlay is made in code") }

    private var room: PinTrayGeometry.Room {
        PinTrayGeometry.Room(
            containerHeight: bounds.height,
            safeAreaTop: safeAreaInsets.top,
            safeAreaBottom: safeAreaInsets.bottom,
            displayCornerRadius: displayRadius
        )
    }

    private var measuredKeyboardHeight: CGFloat {
        // The guide already excludes the bottom safe area, `usesBottomSafeArea` being false, so
        // subtracting it again reads a 337pt keyboard as 311.
        max(0, bounds.maxY - keyboardLayoutGuide.layoutFrame.minY)
    }

    private func apply(_ reaction: PinTrayMachine.Reaction) {
        for effect in reaction.effects {
            switch effect {
            case .dismissKeyboard: endEditing(true)
            }
        }
        reaction.from.map { place($0, animated: false) }
        PinwheelRecorder.note(
            "tray",
            "\(reaction.timeline)  card=\(Int(reaction.to.height)) inset=\(Int(reaction.to.bottomInset)) "
                + "translation=\(Int(reaction.to.translation))  phase=\(machine.phase) fills=\(machine.fills) "
                + "edits=\(machine.edits) keyboard=\(machine.keyboard)"
                + (reaction.effects.isEmpty ? "" : "  effects=\(reaction.effects)")
                + (reaction.dismisses ? "  dismisses" : "")
        )
        let finish: () -> Void = reaction.dismisses ? { [weak self] in self?.tearDown() } : {}
        switch reaction.timeline {
        case .immediate:
            place(reaction.to, animated: false, then: finish)
        case .carriedByKeyboard:
            write(reaction.to)
            finish()
        case .spring(let bounce):
            place(reaction.to, animated: true, bounce: bounce, velocity: reaction.velocity, then: finish)
        case .matching(let timing):
            place(reaction.to, matching: timing, then: finish)
        }
    }

    private func tearDown() {
        standing?.detach()
        removeFromSuperview()
        PinwheelRecorder.stopFollowing()
    }

    private func write(_ geometry: PinTrayGeometry) {
        tray.layer.cornerRadius = geometry.bottomCornerRadius
        height.constant = geometry.height
        offset.constant = -(geometry.bottomInset - machine.keyboard.height)
    }

    private var motion: UIViewPropertyAnimator?

    private func place(
        _ geometry: PinTrayGeometry,
        matching timing: PinTrayMachine.KeyboardTiming,
        then finish: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: timing.duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: UInt(timing.curve) << 16),
            animations: {
                self.write(geometry)
                self.tray.transform = CGAffineTransform(translationX: 0, y: geometry.translation)
                self.dimming.alpha = geometry.dimming
                self.layoutIfNeeded()
            },
            completion: { _ in finish() }
        )
    }

    private func place(
        _ geometry: PinTrayGeometry,
        animated: Bool,
        bounce: CGFloat = trayResizeBounce,
        velocity: CGFloat = 0,
        then finish: @escaping () -> Void = {}
    ) {
        let travelling = geometry.translation - tray.transform.ty
        let draw = {
            self.write(geometry)
            self.tray.transform = CGAffineTransform(translationX: 0, y: geometry.translation)
            self.dimming.alpha = geometry.dimming
            self.layoutIfNeeded()
        }
        motion?.stopAnimation(true)
        motion = nil
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

    private func catchTheMotion() {
        guard motion?.isRunning == true else { return }
        apply(machine.handle(.caught(at: tray.transform.ty)))
    }

    var cardHeight: CGFloat { tray.bounds.height }
    var contentHeight: CGFloat { standing?.body.bounds.height ?? 0 }
    var cardBottom: CGFloat { card.convert(card.bounds, to: self).maxY }
    var bottomCornerRadius: CGFloat { tray.layer.cornerRadius }

    var onBackgroundDismiss: () -> Void = {}
    var onExit: () -> Void = {}
    /// Reduce Motion is the system's to set, so it arrives as a report the machine holds.
    var motionIsReduced: Bool {
        get { machine.motionIsReduced }
        set { machine.motionIsReduced = newValue }
    }

    @objc private func motionPreferenceChanged() {
        machine.motionIsReduced = UIAccessibility.isReduceMotionEnabled
    }
    var depth = 0

    private var contentBottomInset: CGFloat {
        machine.geometry.contentBottomInset
    }

    override func accessibilityPerformEscape() -> Bool {
        onBackgroundDismiss()
        return true
    }

    private func build() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        accessibilityViewIsModal = true
        container.view.addSubview(self)

        dimming.frame = bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.backgroundColor = UIColor.black.withAlphaComponent(trayDimming)
        dimming.alpha = 0
        addSubview(dimming)
        dimming.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(dismissFromBackground))
        )

        machine.motionIsReduced = UIAccessibility.isReduceMotionEnabled
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(motionPreferenceChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardAnnouncedItsMove),
                name: name,
                object: nil
            )
        }

        PinwheelRecorder.follow { [weak self] in
            guard let self else { return [] }
            let card = self.tray.layer.presentation()
            let top = (card?.frame.minY ?? self.tray.frame.minY) + (card?.transform.m42 ?? 0)
            let content = self.standing?.body.layer.presentation()?.bounds.height
                ?? self.standing?.body.bounds.height ?? 0
            return [
                ("cardTop", top),
                ("cardHeight", card?.bounds.height ?? 0),
                ("contentHeight", content),
                ("contentBottom", top + content),
                ("keyboard", self.measuredKeyboardHeight),
            ]
        }

        let screen = container.view.window?.screen ?? UIScreen.main
        displayRadius = screen.pinDisplayCornerRadius
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.layer.cornerRadius = displayRadius
        tray.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tray.layer.cornerCurve = .continuous
        tray.clipsToBounds = true
        addSubview(tray)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .primaryBackground
        card.layer.cornerRadius = trayTopRadius
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        tray.addSubview(card)

        // The keyboard runs out of process and posts its notifications asynchronously, so anything
        // driven off them races its animation; a constraint to this guide is carried by that animation.
        keyboardLayoutGuide.usesBottomSafeArea = false
        height = tray.heightAnchor.constraint(equalToConstant: 0)
        let topLimit = tray.topAnchor.constraint(
            greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
            constant: trayMargin
        )

        height.priority = .defaultHigh
        offset = tray.bottomAnchor.constraint(
            equalTo: keyboardLayoutGuide.topAnchor,
            constant: -trayBottomMargin
        )
        let lifted = tray.bottomAnchor.constraint(
            equalTo: keyboardLayoutGuide.topAnchor,
            constant: -trayKeyboardMargin
        )
        // Toggling these by hand from layoutSubviews re-enters layout and UIKit throws.
        offset.priority = UILayoutPriority(999)
        lifted.priority = UILayoutPriority(999)
        keyboardLayoutGuide.setConstraints([offset], activeWhenNearEdge: .bottom)
        keyboardLayoutGuide.setConstraints([lifted], activeWhenAwayFrom: .bottom)

        rest = tray.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -trayBottomMargin)
        NSLayoutConstraint.activate([
            tray.leadingAnchor.constraint(equalTo: leadingAnchor, constant: trayMargin),
            tray.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trayMargin),
            topLimit,
            height,
            card.leadingAnchor.constraint(equalTo: tray.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: tray.trailingAnchor),
            card.topAnchor.constraint(equalTo: tray.topAnchor),
            card.bottomAnchor.constraint(equalTo: tray.bottomAnchor),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag))
        pan.delegate = self
        tray.addGestureRecognizer(pan)
    }

    private var holdsFirstResponder: Bool {
        func search(_ view: UIView) -> Bool {
            view.isFirstResponder || view.subviews.contains(where: search)
        }
        return search(self)
    }

    @objc private func keyboardAnnouncedItsMove(_ notification: Notification) {
        guard
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
        else { return }
        machine.keyboardTiming = PinTrayMachine.KeyboardTiming(duration: duration, curve: curve)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply(machine.handle(.roomChanged(room)))
        let measured = measuredKeyboardHeight
        guard machine.keyboard(measuring: measured) != machine.keyboard else { return }
        apply(machine.handle(.keyboardMeasured(measured)))
    }

    private func present(_ tray: PinTray) {
        PinwheelRecorder.note("navigation", "present")
        assemble(tray)
        apply(machine.handle(.presented(contentHeight: fittedHeight)))
    }

    func refresh(_ tray: PinTray) {
        guard let standing else { return }
        standing.titleBar.show(titleBarLeaf(tray))
        standing.body.show(inset(tray.content))
        settle()
        if let accessory = standing.accessory, let leaf = accessoryLeaf(tray) {
            accessory.show(leaf)
        }
    }

    func show(_ tray: PinTray, isPush: Bool) {
        PinwheelRecorder.note("navigation", isPush ? "push" : "pop")
        apply(machine.handle(.moveBegan(isPush: isPush)))

        let leaving = standing
        assemble(tray)
        standing?.views.forEach { $0.alpha = 0 }
        layoutIfNeeded()

        let zoom = CGAffineTransform(scaleX: machine.contentZoom, y: machine.contentZoom)
        standing?.dissolving.forEach { $0.transform = isPush ? .identity : zoom }

        let arriving = standing?.commitButton
        let left = leaving?.commitButton
        if let arriving, let left, left.frame == arriving.frame {
            arriving.alpha = 1
            card.bringSubviewToFront(left)
        }

        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.standing?.views.forEach { $0.alpha = 1; $0.transform = .identity }
            leaving?.views.forEach { $0.alpha = 0 }
            leaving?.dissolving.forEach { $0.transform = isPush ? zoom : .identity }
        } completion: { _ in
            leaving?.detach()
        }

        // Whether the arriving tray raises a keyboard is knowable only once it has mounted, and it
        // decides who owns the move.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            apply(machine.handle(.moved(
                contentHeight: fittedHeight,
                edits: holdsFirstResponder,
                isPush: isPush
            )))
        }
    }

    func dismiss() {
        PinwheelRecorder.note("navigation", "dismiss")
        apply(machine.handle(.dismissed))
    }

    private func titleBarLeaf(_ tray: PinTray) -> AnyView {
        AnyView(
            PinTrayTitleBar(
                title: tray.title,
                isRoot: depth == 0,
                accessory: tray.titleAccessory,
                exit: { [weak self] in self?.onExit() }
            )
        )
    }

    private func inset(_ content: AnyView) -> AnyView {
        AnyView(content.padding(.horizontal, trayContentMargin))
    }

    private func accessoryLeaf(_ tray: PinTray) -> AnyView? {
        guard tray.standsACommitButton, let commit = tray.commit else {
            return tray.floating.map(inset)
        }
        return inset(AnyView(
            PinButton(commit.title, action: commit.action)
                .style(.custom(text: .primaryBackground, background: .primaryText))
                .fullWidth()
        ))
    }

    private func assemble(_ tray: PinTray) {
        let titleBar = PinTrayLeafView(showing: titleBarLeaf(tray), in: container)
        let body = PinTrayBodyView(showing: inset(tray.content), in: container)
        let accessory = accessoryLeaf(tray).map { PinTrayLeafView(showing: $0, in: container) }
        let divider = UIView()
        divider.backgroundColor = .tertiaryText

        body.coordinating = self
        for view in [titleBar, divider, body, accessory].compactMap({ $0 }) {
            view.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(view)
        }

        var constraints: [NSLayoutConstraint] = [
            titleBar.topAnchor.constraint(equalTo: card.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            divider.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: trayContentMargin),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -trayContentMargin),
            body.topAnchor.constraint(equalTo: divider.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ]
        if let accessory {
            constraints += [
                accessory.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                accessory.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                accessory.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -accessoryInset),
            ]
        }
        NSLayoutConstraint.activate(constraints)

        let width = bounds.width - trayMargin * 2
        let clearanceAboveAccessory = PinTrayGeometry.clearanceAboveAccessory(floats: tray.floating != nil)
        body.clearance = accessory
            .map { accessoryInset + $0.height(fitting: width) + clearanceAboveAccessory } ?? contentBottomInset
        standing = Standing(
            description: tray,
            titleBar: titleBar,
            body: body,
            accessory: accessory,
            divider: divider
        )
        apply(machine.handle(.fillsReported(tray.detent == .filling)))
        PinwheelRecorder.note("tray", "assembled, measuring \(Int(fittedHeight))")
    }

    private var fittedHeight: CGFloat {
        guard let standing else { return 0 }
        let width = bounds.width - trayMargin * 2
        return standing.titleBar.height(fitting: width)
            + 1
            + standing.body.contentHeight(fitting: width)
    }

    private var accessoryInset: CGFloat { contentBottomInset }

    func settle() {
        let measured = fittedHeight
        guard self.standing != nil, machine.resizes(to: measured) else { return }
        let standing = machine.geometry.height
        PinwheelRecorder.note("reported", "content measures \(Int(measured))  standing=\(Int(standing))")
        apply(machine.handle(.contentResized(measured)))
    }

    @objc private func dismissFromBackground() {
        PinwheelRecorder.note("navigation", "backdrop tapped")
        onBackgroundDismiss()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let travelled = gesture.translation(in: self).y
        switch gesture.state {
        case .began:
            catchTheMotion()
            gesture.setTranslation(CGPoint(x: 0, y: machine.pulledSoFar), in: self)
        case .changed:
            apply(machine.handle(.dragged(travelled)))
        case .ended, .cancelled:
            release(velocity: gesture.velocity(in: self).y)
        default:
            break
        }
    }

    private func release(velocity: CGFloat) {
        let reaction = machine.handle(.released(velocity: velocity))
        if reaction.dismisses {
            onBackgroundDismiss()
        } else {
            apply(reaction)
        }
    }
}

extension PinTrayOverlay: PinTrayBodyCoordinating {
    var cardIsBeingPulled: Bool { machine.cardIsBeingPulled }

    func bodyWillBeginPulling() {
        catchTheMotion()
    }

    func bodyWasPulledDown(by amount: CGFloat) {
        apply(machine.handle(.pulledFurther(amount)))
    }

    func bodyStoppedBeingPulled(velocity: CGFloat) {
        release(velocity: velocity)
    }
}

extension PinTrayOverlay: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let candidate = view, candidate !== tray {
            if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled { return false }
            view = candidate.superview
        }
        return true
    }
}
