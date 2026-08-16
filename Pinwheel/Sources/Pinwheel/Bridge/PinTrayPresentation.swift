import SwiftUI
import UIKit

private let trayDimming: CGFloat = 0.35
// Going deeper, the tray being left grows as it fades; coming back, the one arriving shrinks into
// place. The shallower of the two always carries the zoom, so a sequence reads as depth.
private let trayZoom: CGFloat = 1.08

extension UIScreen {
    /// The display's own corner radius, which a bottom-anchored card has to nest inside to look
    /// continuous with the hardware. UIKit exposes it nowhere public.
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
        // The presenting view re-renders on its own state, and a tray is built from that state — so an
        // unchanged path still has to hand the standing tray its new description, or the tray keeps
        // drawing whatever it was assembled with.
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

        // Finding the container is the coordinator's job: it is the one holding the presenter, and the
        // overlay should be handed where it lives rather than climbing to find it.
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

    /// The tray on screen: three containers the chassis holds and lays out, each with one job. They are
    /// built together and swapped together, so a tray's scroll position is its own.
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
    }

    private var standing: Standing?

    /// Given, not hunted. The overlay used to climb from its own window to the root view controller and
    /// on through whatever it had presented, looking for somewhere to live.
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

    /// All the view knows about the keyboard: how much of the screen it currently takes. What that
    /// means is the machine's to decide.
    private var measuredKeyboardHeight: CGFloat {
        // Measured from the guide's own top edge, because that edge is what the card's bottom is
        // constrained to. Subtracting the bottom safe area here made the machine believe a 337pt
        // keyboard was 311 — the guide already excludes it, `usesBottomSafeArea` being false — so the
        // card came out 26pt too tall and, pinned to the guide below, rode 26pt high until the keyboard
        // left and the resting constraint dropped it back.
        max(0, bounds.maxY - keyboardLayoutGuide.layoutFrame.minY)
    }

    /// Everything the views do comes through here: the machine says where the tray goes and who moves
    /// it, and this is the only place that draws the answer.
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
            // Set the values and let the keyboard's own animation carry them; starting one of ours
            // beside it is what reads as two steps.
            write(reaction.to)
            finish()
        case .spring(let bounce):
            place(reaction.to, animated: true, bounce: bounce, then: finish)
        case .matching(let timing):
            place(reaction.to, matching: timing, then: finish)
        }
    }

    /// Torn down when the travel that carries it away actually ends, which the animation knows and a
    /// timer beside it can only estimate.
    private func tearDown() {
        standing?.detach()
        removeFromSuperview()
        PinwheelRecorder.stopFollowing()
    }

    private func write(_ geometry: PinTrayGeometry) {
        height.constant = geometry.height
        // The guide decides where the card's bottom goes; the geometry decides how far above the guide
        // it stands. One constraint serves a docked keyboard and no keyboard at all, so its margin is
        // whatever the geometry keeps clear beyond the keyboard itself — sixteen above a keyboard, eight
        // above the floor. Fixing it at one of the two left the card eight points out under the other.
        offset.constant = -(geometry.bottomInset - machine.keyboard.height)
    }

    /// Drawn on the keyboard's own clock and curve, started in the same turn the keyboard was asked to
    /// leave — so the two are one motion rather than one following the other.
    private func place(
        _ geometry: PinTrayGeometry,
        matching timing: PinTrayMachine.KeyboardTiming,
        then finish: @escaping () -> Void
    ) {
        write(geometry)
        UIView.animate(
            withDuration: timing.duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: UInt(timing.curve) << 16),
            animations: {
                self.tray.transform = CGAffineTransform(translationX: 0, y: geometry.translation)
                self.tray.layer.cornerRadius = geometry.bottomCornerRadius
                self.dimming.alpha = 0
                self.layoutIfNeeded()
            },
            completion: { _ in finish() }
        )
    }

    private func place(
        _ geometry: PinTrayGeometry,
        animated: Bool,
        bounce: CGFloat = trayResizeBounce,
        then finish: @escaping () -> Void = {}
    ) {
        write(geometry)
        let draw = {
            self.tray.transform = CGAffineTransform(translationX: 0, y: geometry.translation)
            self.tray.layer.cornerRadius = geometry.bottomCornerRadius
            self.dimming.alpha = geometry.translation > 0 && self.machine.phase == .leaving ? 0 : 1
            self.layoutIfNeeded()
        }
        guard animated else { draw(); return finish() }
        UIView.animate(springDuration: trayResizeDuration, bounce: bounce, animations: draw) { _ in finish() }
    }



    /// The card, and the content laid out inside it. Read by tests asserting the two agree.
    var cardHeight: CGFloat { tray.bounds.height }
    var contentHeight: CGFloat { standing?.body.bounds.height ?? 0 }
    /// Where the card's own bottom edge sits, in the overlay.
    var cardBottom: CGFloat { card.convert(card.bounds, to: self).maxY }

    var onBackgroundDismiss: () -> Void = {}
    var onExit: () -> Void = {}
    /// How deep in the flow the standing tray is. Nought means the way out is a cross, not a chevron.
    var depth = 0

    /// What the content keeps clear below itself: the home indicator's own strip, less the margin the
    /// card already stands off the screen by. Lifted onto the keyboard there is no indicator to clear.
    private var contentBottomInset: CGFloat {
        machine.geometry.contentBottomInset
    }

    /// How tall a filling tray stands: all the room there is. Read off the same geometry everything
    /// else is drawn from, so the content and the card can never disagree about it.
    private var standingRoom: CGFloat {
        PinTrayGeometry(
            contentHeight: 0,
            fills: true,
            room: room,
            keyboardInset: machine.keyboard.height,
            standsOnKeyboard: machine.edits
        ).height
    }

    // A hosting controller's view has to live inside its parent controller's own view tree, so the
    // overlay hangs off the container it was given.
    private func build() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(self)

        dimming.frame = bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.backgroundColor = UIColor.black.withAlphaComponent(trayDimming)
        dimming.alpha = 0
        addSubview(dimming)
        dimming.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(dismissFromBackground))
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

        // Laid out by the keyboard rather than reacting to it. The keyboard runs out of process and
        // posts its notifications asynchronously, so anything driven off them is racing the keyboard's
        // own animation; a constraint to this guide is carried *by* that animation, and it brings
        // interactive dismissal with it.
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
        // The guide owns the swap: docked at the bottom edge it uses the resting constraint, lifted
        // away from it the keyboard one, and it exchanges them inside the keyboard's own animation.
        // Toggling these by hand from layoutSubviews re-enters layout and UIKit throws.
        offset.priority = UILayoutPriority(999)
        lifted.priority = UILayoutPriority(999)
        keyboardLayoutGuide.setConstraints([offset], activeWhenNearEdge: .bottom)
        keyboardLayoutGuide.setConstraints([lifted], activeWhenAwayFrom: .bottom)

        // Leaving a tray that was editing, the card takes its resting place at once and lets the
        // keyboard slide off it — the reference moves only the keyboard, never both. Required, so the
        // guide's own constraint yields to it, and released once the keyboard has gone.
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
        // The list's own scrolling recogniser must keep working: this one watches alongside it and only
        // takes over when the list has nothing left to give.
        pan.delegate = self
        tray.addGestureRecognizer(pan)
    }

    /// Whether anything in the tray has focus, and so whether it stands on the keyboard.
    ///
    /// Deliberately not "will a keyboard appear", which two private APIs failed to answer — see
    /// LEARNINGS. The hold that wanted the answer only applies to a tray sized by what it holds, and
    /// none exists, so the question is not asked.
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

    /// The same tray, redrawn. Its containers stay; only what they draw changes.
    func refresh(_ tray: PinTray) {
        guard let standing else { return }
        standing.titleBar.show(titleBarLeaf(tray))
        standing.body.show(tray.content)
        settle()
        if let accessory = standing.accessory, let leaf = accessoryLeaf(tray) {
            accessory.show(leaf)
        }
    }

    func show(_ tray: PinTray, isPush: Bool) {
        PinwheelRecorder.note("navigation", isPush ? "push" : "pop")
        // Sent now, synchronously: the arriving tray describes itself before this move resolves.
        apply(machine.handle(.moveBegan(isPush: isPush)))

        let leaving = standing
        assemble(tray)
        standing?.views.forEach { $0.alpha = 0 }
        layoutIfNeeded()

        // The dissolve is the content changing rather than the card moving, so it runs at once and on
        // its own timeline, never waiting on a keyboard. Going deeper the tray being left grows as it
        // fades; coming back the one arriving shrinks into place, so a sequence reads as depth.
        let zoom = CGAffineTransform(scaleX: trayZoom, y: trayZoom)
        standing?.views.forEach { $0.transform = isPush ? .identity : zoom }
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.standing?.views.forEach { $0.alpha = 1; $0.transform = .identity }
            leaving?.views.forEach { $0.alpha = 0; $0.transform = isPush ? zoom : .identity }
        } completion: { _ in
            leaving?.detach()
        }

        // Whether the arriving tray raises the keyboard is only knowable once it has mounted, and it
        // decides who owns the move — so the machine hears about it a turn later.
        DispatchQueue.main.async {
            self.apply(self.machine.handle(.moved(
                contentHeight: self.fittedHeight,
                edits: self.holdsFirstResponder,
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

    /// What stands at the bottom: whatever the tray floats, or the button that ends the flow.
    private func accessoryLeaf(_ tray: PinTray) -> AnyView? {
        if let floating = tray.floating { return floating }
        guard let commit = tray.commit else { return nil }
        return AnyView(
            PinButton(commit.title, action: commit.action)
                .style(.custom(text: .primaryBackground, background: .primaryText))
                .fullWidth()
                .padding(.horizontal, .spacingXL)
        )
    }

    /// Builds a tray's three containers and hangs them in the card. Layout is the chassis's: the title
    /// bar at the top, the body filling everything under it, and the accessory standing over the body at
    /// the bottom — which is why the body keeps clearance below its last row rather than stopping short.
    private func assemble(_ tray: PinTray) {
        let titleBar = PinTrayLeafView(showing: titleBarLeaf(tray), in: container)
        let body = PinTrayBodyView(showing: tray.content, in: container)
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
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: .spacingXL),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -.spacingXL),
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
        // Measured up from the card's bottom: the room the accessory stands off, its own height, and a
        // gap so the last row does not sit against it.
        body.clearance = accessory
            .map { accessoryInset + $0.height(fitting: width) + .spacingS } ?? contentBottomInset
        standing = Standing(
            description: tray,
            titleBar: titleBar,
            body: body,
            accessory: accessory,
            divider: divider
        )
        // How a tray stands is part of its description now, so the machine hears it as the tray is
        // built rather than whenever SwiftUI got round to reporting a preference.
        apply(machine.handle(.fillsReported(tray.detent == .filling)))
        PinwheelRecorder.note("tray", "assembled, measuring \(Int(fittedHeight))")
    }

    /// A tray sized by what it holds is its parts added up.
    private var fittedHeight: CGFloat {
        guard let standing else { return 0 }
        let width = bounds.width - trayMargin * 2
        return standing.titleBar.height(fitting: width)
            + 1
            + standing.body.contentHeight(fitting: width)
    }

    /// The same clearance content keeps at the bottom of a tray. A commit button is the lowest thing on
    /// the screen, so it has to stand off the home indicator by what everything else does — a flat
    /// margin put it inside that strip.
    private var accessoryInset: CGFloat { contentBottomInset }

    /// Content changing inside a standing tray resizes it, clamped to the room there is. This is not
    /// navigation, so it moves without bounce — an overshoot here reverses direction under the reader.
    func settle() {
        let standing = machine.geometry.height
        let measured = fittedHeight
        guard measured > 0, self.standing != nil, abs(measured - standing) > 0.5 else { return }
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
        case .changed:
            apply(machine.handle(.dragged(travelled)))
        case .ended, .cancelled:
            let reaction = machine.handle(.released(
                velocity: gesture.velocity(in: self).y,
                dismissBeyond: height.constant / 3
            ))
            if reaction.dismisses {
                onBackgroundDismiss()
            } else {
                apply(reaction)
            }
        default:
            break
        }
    }
}

extension PinTrayOverlay: PinTrayBodyCoordinating {
    /// The body says it was pulled with nothing left to scroll. What that means for the card is the
    /// chassis's to decide — the body never knew there was one.
    func bodyWasPulledDown(by amount: CGFloat) {
        apply(machine.handle(.dragged(amount)))
    }

    func bodyStoppedBeingPulled(velocity: CGFloat) {
        let reaction = machine.handle(.released(velocity: velocity, dismissBeyond: cardHeight / 3))
        apply(reaction)
        if reaction.dismisses { onBackgroundDismiss() }
    }
}

extension PinTrayOverlay: UIGestureRecognizerDelegate {
    /// The card is dragged by its chrome; a touch in the body belongs to the body — but only while the
    /// body has somewhere to go. Rows that already fit never scroll, so the drag is the card's.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let candidate = view, candidate !== tray {
            if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled { return false }
            view = candidate.superview
        }
        return true
    }
}
