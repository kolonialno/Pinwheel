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

    var onBackgroundDismiss: () -> Void = {}

    /// A card standing above the keyboard clears it by more than it clears the screen's own edge.
    private var bottomInset: CGFloat {
        keyboardInset > 0 ? keyboardInset + trayKeyboardMargin : trayBottomMargin
    }

    /// What the content keeps clear below itself: the home indicator's own strip, less the margin the
    /// card already stands off the screen by. Lifted onto the keyboard there is no indicator to clear.
    private var contentBottomInset: CGFloat {
        keyboardInset > 0 ? .spacingL : max(safeAreaInsets.bottom - trayBottomMargin, .spacingL)
    }

    private var ceiling: CGFloat {
        bounds.height - safeAreaInsets.top - trayMargin - bottomInset
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

        height = tray.heightAnchor.constraint(equalToConstant: 0)
        offset = tray.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -trayBottomMargin)
        NSLayoutConstraint.activate([
            tray.leadingAnchor.constraint(equalTo: leadingAnchor, constant: trayMargin),
            tray.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trayMargin),
            height,
            offset,
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardChanged),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    // Standing clear of the bottom edge, the card is no longer nested in the display's corner, so its
    // bottom pair drops to the same radius as its top.
    @objc private func keyboardChanged(_ note: Notification) {
        guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, bounds.maxY - convert(end, from: nil).minY)
        guard overlap != keyboardInset else { return }
        keyboardInset = overlap

        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? trayResizeDuration
        let curve = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int).map {
            UIView.AnimationOptions(rawValue: UInt($0) << 16)
        } ?? []

        offset.constant = -bottomInset
        standingHeight = min(fittedHeight, ceiling)
        height.constant = standingHeight
        currentHeight?.constant = fittedHeight
        UIView.animate(withDuration: duration, delay: 0, options: curve) {
            self.tray.layer.cornerRadius = self.keyboardInset > 0 ? trayTopRadius : self.displayRadius
            self.layoutIfNeeded()
        }
    }

    func present(_ content: AnyView) {
        mount(content)
        height.constant = standingHeight
        offset.constant = standingHeight
        layoutIfNeeded()

        offset.constant = -bottomInset
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.dimming.alpha = 1
            self.layoutIfNeeded()
        }
    }

    func refresh(_ content: AnyView) {
        current?.rootView = content
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

        height.constant = standingHeight
        withAnimation(.trayContent) {
            leavingPhase?.contentZoom = isPush ? trayZoom : 1
            self.currentPhase?.contentZoom = 1
        }
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.current?.view.alpha = 1
            leaving?.view.alpha = 0
            self.layoutIfNeeded()
        } completion: { _ in
            leaving.map(self.unmount)
        }
    }

    func dismiss() {
        offset.constant = standingHeight
        UIView.animate(springDuration: trayResizeDuration, bounce: 0) {
            self.dimming.alpha = 0
            self.layoutIfNeeded()
        } completion: { _ in
            self.current.map(self.unmount)
            self.removeFromSuperview()
        }
    }

    private func mount(_ content: AnyView, entering: CGFloat = 1) {
        let phase = PinTrayPhase()
        phase.contentZoom = entering
        let hosting = UIHostingController(rootView: AnyView(
            content
                .environment(\.pinTrayPhase, phase)
                .environment(\.pinTrayBottomInset, contentBottomInset)
        ))
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
        standingHeight = min(fitted, ceiling)

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

    /// Content changing inside a standing tray — a search filtering down — resizes it, clamped to the
    /// room there is.
    func settle(to content: CGFloat) {
        guard content > 0, current != nil else { return }
        fittedHeight = content
        let target = min(content, ceiling)
        guard abs(target - standingHeight) > 0.5 else { return }

        standingHeight = target
        currentHeight?.constant = content
        height.constant = target
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.layoutIfNeeded()
        }
    }

    @objc private func dismissFromBackground() {
        onBackgroundDismiss()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let travelled = gesture.translation(in: self).y

        switch gesture.state {
        case .changed:
            offset.constant = -bottomInset + max(0, travelled)
            dimming.alpha = 1 - (max(0, travelled) / max(height.constant, 1)) * 0.6
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).y
            if velocity > trayDismissVelocity || travelled > height.constant / 3 {
                onBackgroundDismiss()
            } else {
                offset.constant = -bottomInset
                UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
                    self.dimming.alpha = 1
                    self.layoutIfNeeded()
                }
            }
        default:
            break
        }
    }
}
