import SwiftUI
import UIKit

private let trayResizeDuration: TimeInterval = 0.30
private let trayResizeBounce: CGFloat = 0.10
private let trayDismissVelocity: CGFloat = 800
private let trayDimming: CGFloat = 0.35
private let trayMargin: CGFloat = .spacingS
private let trayBottomMargin: CGFloat = .spacingS
private let trayKeyboardMargin: CGFloat = .spacingL
// Going deeper, the tray being left grows as it fades; coming back, the one arriving shrinks into
// place. The shallower of the two always carries the zoom, so a sequence reads as depth.
private let trayZoom: CGFloat = 1.08
private let trayTopRadius: CGFloat = 32

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
    private var keyboardInset: CGFloat = 0
    private var fittedHeight: CGFloat = 0
    private var currentHeight: NSLayoutConstraint?
    private var currentPhase: PinTrayPhase?
    private var standingHeight: CGFloat = 0
    private var dragOffset: CGFloat = 0
    private var lastContent: AnyView?
    private var rest: NSLayoutConstraint?


    var onBackgroundDismiss: () -> Void = {}

    /// What the content keeps clear below itself: the home indicator's own strip, less the margin the
    /// card already stands off the screen by. Lifted onto the keyboard there is no indicator to clear.
    private var contentBottomInset: CGFloat {
        max(safeAreaInsets.bottom - trayBottomMargin, .spacingL)
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
    override func layoutSubviews() {
        super.layoutSubviews()
        let lifted = keyboardLayoutGuide.layoutFrame.minY < bounds.maxY - safeAreaInsets.bottom - 1
        let radius = lifted ? trayTopRadius : displayRadius
        if tray.layer.cornerRadius != radius {
            tray.layer.cornerRadius = radius
        }
    }

    /// The card's geometry is one thing — how tall it stands, how far it sits off the bottom, and the
    /// corner that depends on whether it is still nested in the display's own. Every trigger re-targets
    /// this one spring rather than starting a second animation over the first: two curves running on
    /// the same constraint is what made leaving a tray with the keyboard up read as two steps.
    private func settleGeometry(
        animated: Bool,
        bounce: CGFloat = trayResizeBounce,
        alongside: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        standingHeight = fittedHeight
        height.constant = standingHeight
        currentHeight?.constant = fittedHeight
        // Where the tray lives is layout, and the keyboard guide owns it; entering, leaving and
        // dragging are a transform over that, so a gesture never fights the guide's constraints.
        tray.transform = dragOffset > 0 ? CGAffineTransform(translationX: 0, y: dragOffset) : .identity
        let radius = keyboardInset > 0 ? trayTopRadius : displayRadius

        guard animated else {
            tray.layer.cornerRadius = radius
            alongside?()
            layoutIfNeeded()
            completion?()
            return
        }
        UIView.animate(springDuration: trayResizeDuration, bounce: bounce) {
            self.tray.layer.cornerRadius = radius
            alongside?()
            self.layoutIfNeeded()
        } completion: { _ in
            completion?()
        }
    }

    func present(_ content: AnyView) {
        mount(content)
        height.constant = standingHeight
        layoutIfNeeded()
        tray.transform = CGAffineTransform(translationX: 0, y: standingHeight + trayBottomMargin)
        settleGeometry(animated: true) { self.dimming.alpha = 1 }
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

        if !isPush { rest?.isActive = true }
        mount(content, entering: isPush ? 1 : trayZoom)
        current?.view.alpha = 0
        layoutIfNeeded()

        withAnimation(.trayContent) {
            leavingPhase?.contentZoom = isPush ? trayZoom : 1
            self.currentPhase?.contentZoom = 1
        }
        settleGeometry(animated: true) {
            self.current?.view.alpha = 1
            leaving?.view.alpha = 0
        } completion: {
            leaving.map(self.unmount)
            self.rest?.isActive = false
        }
    }

    func dismiss() {
        dragOffset = standingHeight + trayBottomMargin
        settleGeometry(animated: true, bounce: 0) {
            self.dimming.alpha = 0
        } completion: {
            self.current.map(self.unmount)
            self.removeFromSuperview()
        }
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
        guard content > 0, current != nil else { return }
        fittedHeight = content
        guard abs(content - standingHeight) > 0.5 else { return }
        settleGeometry(animated: true, bounce: 0)
    }

    @objc private func dismissFromBackground() {
        onBackgroundDismiss()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let travelled = gesture.translation(in: self).y

        switch gesture.state {
        case .changed:
            dragOffset = max(0, travelled)
            settleGeometry(animated: false)
            dimming.alpha = 1 - (dragOffset / max(height.constant, 1)) * 0.6
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).y
            let leaving = velocity > trayDismissVelocity || travelled > height.constant / 3
            dragOffset = 0
            if leaving {
                onBackgroundDismiss()
            } else {
                settleGeometry(animated: true) { self.dimming.alpha = 1 }
            }
        default:
            break
        }
    }
}
