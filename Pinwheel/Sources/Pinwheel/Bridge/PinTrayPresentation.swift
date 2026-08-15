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
                        .onPreferenceChange(PinTrayFillsKey.self) { fills in
                            coordinator.trayFillsChanged(fills)
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

    func trayFillsChanged(_ fills: Bool) {
        overlay?.trayFills(fills)
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

        // Finding the container is the coordinator's job: it is the one holding the presenter, and the
        // overlay should be handed where it lives rather than climbing to find it.
        guard var container = presenter.view.window?.rootViewController else { return }
        while let presented = container.presentedViewController { container = presented }

        let created = PinTrayOverlay(in: container, showing: content)
        created.onBackgroundDismiss = { [weak self] in self?.dismissAll() }
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
    private var rest = NSLayoutConstraint()
    private var displayRadius: CGFloat = .radiusL
    private var fittedHeight: CGFloat = 0
    private lazy var machine = PinTrayMachine(room: room)

    /// What is on screen right now. One value, because a hosting controller, the constraint holding it
    /// and the phase driving it are only ever meaningful together.
    private struct Mounted {
        let hosting: UIHostingController<AnyView>
        let height: NSLayoutConstraint
        let phase: PinTrayPhase
    }

    private var mounted: Mounted?

    /// Given, not hunted. The overlay used to climb from its own window to the root view controller and
    /// on through whatever it had presented, looking for somewhere to live.
    private unowned let container: UIViewController
    init(in container: UIViewController, showing content: AnyView) {
        self.container = container
        super.init(frame: container.view.bounds)
        build()
        present(content)
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
        mounted.map { unmount($0.hosting) }
        removeFromSuperview()
        PinwheelRecorder.stopFollowing()
    }

    /// How tall the content stands inside a card of this height. Arriving, or filling, it is exactly the
    /// card: shorter and anything anchored to its bottom floats mid-card, taller and the card becomes a
    /// window onto nothing. Only a tray that has arrived and is sized by what it holds keeps its own
    /// height, which is what the chassis scroll is for.
    private func contentHeight(standingIn card: CGFloat) -> CGFloat {
        machine.fills || machine.phase.isResolvingAMove ? card : max(fittedHeight, card)
    }

    private func write(_ geometry: PinTrayGeometry) {
        height.constant = geometry.height
        // The guide decides where the card's bottom goes; the geometry decides how far above the guide
        // it stands. One constraint serves a docked keyboard and no keyboard at all, so its margin is
        // whatever the geometry keeps clear beyond the keyboard itself — sixteen above a keyboard, eight
        // above the floor. Fixing it at one of the two left the card eight points out under the other.
        offset.constant = -(geometry.bottomInset - machine.keyboard.height)
        // A filling tray is as tall as the card; a fitting one keeps its own height and scrolls when
        // the card is smaller than it.
        // The chassis scrolls only to rescue a tray taller than its card. A filling tray is exactly as
        // tall as its card, so leaving it enabled hands it the drag meant for the content.
        scroll.isScrollEnabled = !machine.fills
        mounted?.height.constant = contentHeight(standingIn: geometry.height)
        mounted?.phase.standingRoom = geometry.height
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
    var contentHeight: CGFloat { mounted?.hosting.view.bounds.height ?? 0 }

    var onBackgroundDismiss: () -> Void = {}

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
            let content = self.mounted?.hosting.view.layer.presentation()?.bounds.height
                ?? self.mounted?.hosting.view.bounds.height ?? 0
            return [
                ("cardTop", top),
                ("cardHeight", card?.bounds.height ?? 0),
                ("contentHeight", content),
                ("contentBottom", top + content),
                ("keyboard", self.measuredKeyboardHeight),
                ("scrollOffset", self.scroll.contentOffset.y),
                ("scrollContent", self.scroll.contentSize.height),
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

    /// Whether this tray will raise a keyboard: something in it has focus, and a keyboard would appear.
    /// With a hardware keyboard attached the first half is true and the second is not, and a tray that
    /// believed the first alone waited forever for a keyboard that was never coming.
    private var raisesTheKeyboard: Bool {
        holdsFirstResponder && PinTrayKeyboardPresence.aKeyboardWouldAppear
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

    private func present(_ content: AnyView) {
        PinwheelRecorder.note("navigation", "present")
        mount(content)
        apply(machine.handle(.presented(contentHeight: fittedHeight)))
    }

    func refresh(_ content: AnyView) {
        guard let mounted else { return }
        mounted.hosting.rootView = wrap(content, phase: mounted.phase)
    }

    func show(_ content: AnyView, isPush: Bool) {
        PinwheelRecorder.note("navigation", isPush ? "push" : "pop")
        // Sent now, synchronously: the arriving tray describes itself before this move resolves.
        apply(machine.handle(.moveBegan(isPush: isPush)))
        // The tray it is leaving is detached from the scroll view and held at the frame it already
        // has, so it cannot re-lay itself out while it fades and cannot drive the scroll size.
        let leaving = mounted
        if let leaving {
            let size = leaving.hosting.view.bounds.size
            leaving.hosting.view.translatesAutoresizingMaskIntoConstraints = true
            card.addSubview(leaving.hosting.view)
            leaving.hosting.view.frame = CGRect(origin: .zero, size: size)
        }

        mount(content, entering: isPush ? 1 : trayZoom)
        mounted?.hosting.view.alpha = 0
        layoutIfNeeded()

        // The dissolve is the content changing rather than the card moving, so it runs at once and on
        // its own timeline, never waiting on a keyboard.
        withAnimation(.trayContent) {
            leaving?.phase.contentZoom = isPush ? trayZoom : 1
            self.mounted?.phase.contentZoom = 1
        }
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.mounted?.hosting.view.alpha = 1
            leaving?.hosting.view.alpha = 0
        } completion: { _ in
            leaving.map { self.unmount($0.hosting) }
        }

        // Whether the arriving tray raises the keyboard is only knowable once it has mounted, and it
        // decides who owns the move — so the machine hears about it a turn later.
        DispatchQueue.main.async {
            self.apply(self.machine.handle(.moved(
                contentHeight: self.fittedHeight,
                edits: self.raisesTheKeyboard,
                isPush: isPush
            )))
        }
    }

    func trayFills(_ fills: Bool) {
        PinwheelRecorder.note("reported", "fills=\(fills)")
        apply(machine.handle(.fillsReported(fills)))
    }

    func dismiss() {
        PinwheelRecorder.note("navigation", "dismiss")
        apply(machine.handle(.dismissed))
    }

    private func wrap(_ content: AnyView, phase: PinTrayPhase) -> AnyView {
        AnyView(
            content
                .environment(\.pinTrayPhase, phase)
                .environment(\.pinTrayBottomInset, contentBottomInset)
        )
    }

    private func mount(_ content: AnyView, entering: CGFloat = 1) {
        defer { PinwheelRecorder.note("tray", "mounted, measuring \(Int(fittedHeight))") }
        let phase = PinTrayPhase()
        phase.contentZoom = entering
        let hosting = UIHostingController(rootView: wrap(content, phase: phase))
        // The tray adds the home-indicator inset itself, and SwiftUI applying it too measures it twice.
        hosting.safeAreaRegions = []
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addChild(hosting)
        scroll.addSubview(hosting.view)
        hosting.didMove(toParent: container)

        let fitted = hosting.sizeThatFits(
            in: CGSize(width: bounds.width - trayMargin * 2, height: .greatestFiniteMagnitude)
        ).height

        fittedHeight = fitted

        // Held at its full height inside the scroll view, so a tray clamped by the room it has scrolls
        // rather than clipping, and neither view re-lays out during a dissolve. Never shorter than the
        // card it is arriving into: anything anchored to the content's bottom edge would otherwise sit
        // at the arriving tray's own measured height until the move resolved, which is where the search
        // field was appearing — mid-card, then travelling down.
        let contentHeight = hosting.view.heightAnchor.constraint(
            equalToConstant: tray.bounds.height > 0
                ? self.contentHeight(standingIn: tray.bounds.height)
                : fitted
        )
        NSLayoutConstraint.activate([
            hosting.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            hosting.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            contentHeight,
        ])

        mounted = Mounted(hosting: hosting, height: contentHeight, phase: phase)
    }

    private func unmount(_ hosting: UIHostingController<AnyView>) {
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }

    /// Content changing inside a standing tray resizes it, clamped to the room there is. This is not
    /// navigation, so it moves without bounce — an overshoot here reverses direction under the reader.
    func settle(to content: CGFloat) {
        let standing = machine.geometry.height
        PinwheelRecorder.note("reported", "content measures \(Int(content))  standing=\(Int(standing))")
        guard content > 0, mounted != nil, abs(content - standing) > 0.5 else { return }
        apply(machine.handle(.contentResized(content)))
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
