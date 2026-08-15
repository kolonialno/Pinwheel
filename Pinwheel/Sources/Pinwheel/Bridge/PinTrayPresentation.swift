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
    public func pinwheelTray<Item: Hashable, TrayContent: SwiftUI.View>(
        path: SwiftUI.Binding<[Item]>,
        @ViewBuilder content: @escaping (Item) -> TrayContent
    ) -> some SwiftUI.View {
        background(PinTrayPresenter(path: path, content: content))
    }
}

private struct PinTrayPresenter<Item: Hashable, TrayContent: SwiftUI.View>: UIViewControllerRepresentable {
    @SwiftUI.Binding var path: [Item]
    let content: (Item) -> TrayContent

    func makeCoordinator() -> PinTrayCoordinator<Item> {
        PinTrayCoordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismissAll = { path.removeAll() }
        coordinator.sync(
            path: path,
            from: controller,
            tray: { item, depth in
                AnyView(
                    content(item)
                        .environment(\.pinTrayDepth, depth)
                        .environment(\.pinTrayExit) {
                            if depth == 0 { path.removeAll() } else { path.removeLast() }
                        }
                        // Its own ideal height, not the height of the box it was put in, so content
                        // that changes while the tray stands reports the tray's new size.
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            coordinator.contentHeightChanged(height)
                        }
                )
            }
        )
    }
}

final class PinTrayCoordinator<Item: Hashable> {
    private var overlay: PinTrayOverlay?
    private var shown: [Item] = []

    var dismissAll: () -> Void = {}

    func contentHeightChanged(_ height: CGFloat) {
        overlay?.settle(to: height)
    }

    func sync(
        path: [Item],
        from presenter: UIViewController,
        tray: (Item, Int) -> AnyView
    ) {
        // The presenting view re-renders on its own state, and a tray's content is built from that
        // state — so an unchanged path still has to hand the standing tray its new content, or the
        // tray keeps rendering whatever it was mounted with.
        guard path != shown else {
            if let top = path.last {
                overlay?.refresh(tray(top, path.count - 1))
            }
            return
        }
        defer { shown = path }

        guard let top = path.last else {
            overlay?.dismiss()
            overlay = nil
            return
        }

        let content = tray(top, path.count - 1)

        if let overlay {
            overlay.show(content, isPush: path.count >= shown.count)
            return
        }

        guard var top = presenter.view.window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }

        let created = PinTrayOverlay()
        created.onBackgroundDismiss = { [weak self] in self?.dismissAll() }
        created.install(over: top)
        created.present(content)
        overlay = created
    }
}

final class PinTrayOverlay: UIView {
    private let dimming = UIView()
    private let tray = UIView()
    private let card = UIView()
    private let scroll = UIScrollView()
    private var height = NSLayoutConstraint()
    private var offset = NSLayoutConstraint()
    private var current: UIHostingController<AnyView>?
    private weak var parent: UIViewController?
    private var displayRadius: CGFloat = .radiusL
    private var fittedHeight: CGFloat = 0
    private var currentHeight: NSLayoutConstraint?
    private var currentPhase: PinTrayPhase?
    private var standingHeight: CGFloat = 0
    private var dragOffset: CGFloat = 0
    private var lastContent: AnyView?
    private var rest: NSLayoutConstraint?
    private lazy var machine = PinTrayMachine(room: room)

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
        max(0, bounds.maxY - keyboardLayoutGuide.layoutFrame.minY - safeAreaInsets.bottom)
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
        switch reaction.timeline {
        case .immediate:
            place(reaction.to, animated: false)
        case .carriedByKeyboard:
            // Set the values and let the keyboard's own animation carry them; starting one of ours
            // beside it is what reads as two steps.
            write(reaction.to)
        case .spring(let bounce):
            place(reaction.to, animated: true, bounce: bounce)
        case .matching(let timing):
            place(reaction.to, matching: timing)
        }
        if reaction.dismisses {
            let travel: TimeInterval
            switch reaction.timeline {
            case .matching(let timing): travel = timing.duration
            default: travel = trayResizeDuration
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + travel) {
                self.current.map(self.unmount)
                self.removeFromSuperview()
            }
        }
    }

    private func write(_ geometry: PinTrayGeometry) {
        standingHeight = geometry.height
        height.constant = geometry.height
        currentHeight?.constant = fittedHeight
    }

    /// Drawn on the keyboard's own clock and curve, started in the same turn the keyboard was asked to
    /// leave — so the two are one motion rather than one following the other.
    private func place(_ geometry: PinTrayGeometry, matching timing: PinTrayMachine.KeyboardTiming) {
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
            }
        )
    }

    private func place(_ geometry: PinTrayGeometry, animated: Bool, bounce: CGFloat = trayResizeBounce) {
        write(geometry)
        let draw = {
            self.tray.transform = CGAffineTransform(translationX: 0, y: geometry.translation)
            self.tray.layer.cornerRadius = geometry.bottomCornerRadius
            self.dimming.alpha = geometry.translation > 0 && self.machine.phase == .leaving ? 0 : 1
            self.layoutIfNeeded()
        }
        guard animated else { return draw() }
        UIView.animate(springDuration: trayResizeDuration, bounce: bounce, animations: draw)
    }



    var onBackgroundDismiss: () -> Void = {}

    /// What the content keeps clear below itself: the home indicator's own strip, less the margin the
    /// card already stands off the screen by. Lifted onto the keyboard there is no indicator to clear.
    private var contentBottomInset: CGFloat {
        geometry(.resting).contentBottomInset
    }

    /// A tray standing at medium keeps that height whether or not the keyboard is up, so a list that
    /// filters as you type does not move the card. The room still wins where there is less of it.
    private var mediumHeight: CGFloat {
        bounds.height * 0.5
    }

    // A hosting controller's view has to live inside its parent controller's own view tree, so the
    // overlay hangs off the topmost controller rather than straight off the window.
    func install(over controller: UIViewController) {
        parent = controller
        frame = controller.view.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(self)

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

        let screen = controller.view.window?.screen ?? UIScreen.main
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

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        card.addSubview(scroll)

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
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        tray.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag)))
    }

    // Whether the card is still nested in the display's corner is the one thing no constraint can
    // express, so it is read where the guide has already been laid out.
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
        machine.room = room
        let measured = measuredKeyboardHeight
        guard machine.keyboard(measuring: measured) != machine.keyboard else { return }
        apply(machine.handle(.keyboardMeasured(measured)))
    }

    /// The one place a tray's rules are evaluated. Everything below is a projection of this value, so
    /// the rules themselves are unit tests rather than screen recordings.
    private func geometry(_ phase: PinTrayGeometry.Phase) -> PinTrayGeometry {
        PinTrayGeometry(
            contentHeight: fittedHeight,
            room: PinTrayGeometry.Room(
                containerHeight: bounds.height,
                safeAreaTop: safeAreaInsets.top,
                safeAreaBottom: safeAreaInsets.bottom,
                displayCornerRadius: displayRadius
            ),
            keyboardInset: machine.keyboard.height,
            dragOffset: dragOffset,
            phase: phase,
            standsOnKeyboard: rest?.isActive != true
        )
    }

    private func settleGeometry(
        animated: Bool,
        phase: PinTrayGeometry.Phase = .resting,
        bounce: CGFloat = trayResizeBounce,
        alongside: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        let geometry = geometry(phase)
        standingHeight = geometry.height
        height.constant = geometry.height
        currentHeight?.constant = fittedHeight

        // Applied together and only here, so nothing can be assigned outside the animation and arrive
        // already in place.
        let apply = {
            self.tray.transform = CGAffineTransform(translationX: 0, y: geometry.translation)
            self.tray.layer.cornerRadius = geometry.bottomCornerRadius
            alongside?()
            self.layoutIfNeeded()
        }

        guard animated else {
            apply()
            completion?()
            return
        }
        UIView.animate(springDuration: trayResizeDuration, bounce: bounce) {
            apply()
        } completion: { _ in
            completion?()
        }
    }

    func present(_ content: AnyView) {
        mount(content)
        apply(machine.handle(.presented(contentHeight: fittedHeight)))
    }

    func refresh(_ content: AnyView) {
        guard let phase = currentPhase else { return }
        lastContent = content
        current?.rootView = wrap(content, phase: phase)
    }

    func show(_ content: AnyView, isPush: Bool) {
        // The tray it is leaving is detached from the scroll view and held at the frame it already
        // has, so it cannot re-lay itself out while it fades and cannot drive the scroll size.
        let leaving = current
        let leavingPhase = currentPhase
        if let leaving {
            let size = leaving.view.bounds.size
            leaving.view.translatesAutoresizingMaskIntoConstraints = true
            card.addSubview(leaving.view)
            leaving.view.frame = CGRect(origin: .zero, size: size)
        }

        mount(content, entering: isPush ? 1 : trayZoom)
        current?.view.alpha = 0
        layoutIfNeeded()

        // The dissolve is the content changing rather than the card moving, so it runs at once and on
        // its own timeline, never waiting on a keyboard.
        withAnimation(.trayContent) {
            leavingPhase?.contentZoom = isPush ? trayZoom : 1
            self.currentPhase?.contentZoom = 1
        }
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.current?.view.alpha = 1
            leaving?.view.alpha = 0
        } completion: { _ in
            leaving.map(self.unmount)
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
        apply(machine.handle(.dismissed))
    }

    private func wrap(_ content: AnyView, phase: PinTrayPhase) -> AnyView {
        AnyView(
            content
                .environment(\.pinTrayPhase, phase)
                .environment(\.pinTrayBottomInset, contentBottomInset)
                .environment(\.pinTrayMediumHeight, mediumHeight)
        )
    }

    private func mount(_ content: AnyView, entering: CGFloat = 1) {
        let phase = PinTrayPhase()
        phase.contentZoom = entering
        lastContent = content
        let hosting = UIHostingController(rootView: wrap(content, phase: phase))
        // The tray adds the home-indicator inset itself, and SwiftUI applying it too measures it twice.
        hosting.safeAreaRegions = []
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        parent?.addChild(hosting)
        scroll.addSubview(hosting.view)
        hosting.didMove(toParent: parent)

        let fitted = hosting.sizeThatFits(
            in: CGSize(width: bounds.width - trayMargin * 2, height: .greatestFiniteMagnitude)
        ).height

        fittedHeight = fitted
        standingHeight = fitted

        // Held at its full height inside the scroll view, so a tray clamped by the room it has
        // scrolls rather than clipping, and neither view re-lays out during a dissolve.
        let contentHeight = hosting.view.heightAnchor.constraint(equalToConstant: fitted)
        NSLayoutConstraint.activate([
            hosting.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            hosting.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            contentHeight,
        ])

        current = hosting
        currentHeight = contentHeight
        currentPhase = phase
    }

    private func unmount(_ hosting: UIHostingController<AnyView>) {
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }

    /// Content changing inside a standing tray resizes it, clamped to the room there is. This is not
    /// navigation, so it moves without bounce — an overshoot here reverses direction under the reader.
    func settle(to content: CGFloat) {
        guard content > 0, current != nil, abs(content - standingHeight) > 0.5 else { return }
        apply(machine.handle(.contentResized(content)))
    }

    @objc private func dismissFromBackground() {
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
