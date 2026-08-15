import SwiftUI
import UIKit

private let trayResizeDuration: TimeInterval = 0.30
private let trayResizeBounce: CGFloat = 0.10
private let trayDismissVelocity: CGFloat = 800
private let trayDimming: CGFloat = 0.35
private let trayMargin: CGFloat = .spacingS
private let trayBottomMargin: CGFloat = .spacingS
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
                )
            }
        )
    }
}

final class PinTrayCoordinator<Item: Hashable> {
    private var overlay: PinTrayOverlay?
    private var shown: [Item] = []

    var dismissAll: () -> Void = {}

    func sync(
        path: [Item],
        from presenter: UIViewController,
        tray: (Item, Int) -> AnyView
    ) {
        guard path != shown else { return }
        defer { shown = path }

        guard let top = path.last else {
            overlay?.dismiss()
            overlay = nil
            return
        }

        let content = tray(top, path.count - 1)

        if let overlay {
            overlay.show(content)
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
    private var height = NSLayoutConstraint()
    private var offset = NSLayoutConstraint()
    private var current: UIHostingController<AnyView>?
    private weak var parent: UIViewController?
    private var displayRadius: CGFloat = .radiusL
    private var keyboardInset: CGFloat = 0
    private var standingHeight: CGFloat = 0

    var onBackgroundDismiss: () -> Void = {}

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

        offset.constant = -(trayBottomMargin + keyboardInset)
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

        offset.constant = -(trayBottomMargin + keyboardInset)
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.dimming.alpha = 1
            self.layoutIfNeeded()
        }
    }

    func show(_ content: AnyView) {
        let outgoing = current
        mount(content)
        current?.view.alpha = 0
        layoutIfNeeded()

        height.constant = standingHeight
        UIView.animate(springDuration: trayResizeDuration, bounce: trayResizeBounce) {
            self.current?.view.alpha = 1
            outgoing?.view.alpha = 0
            self.layoutIfNeeded()
        } completion: { _ in
            outgoing.map(self.unmount)
        }
    }

    func dismiss() {
        offset.constant = height.constant
        UIView.animate(springDuration: trayResizeDuration, bounce: 0) {
            self.dimming.alpha = 0
            self.layoutIfNeeded()
        } completion: { _ in
            self.current.map(self.unmount)
            self.removeFromSuperview()
        }
    }

    private func mount(_ content: AnyView) {
        let hosting = UIHostingController(rootView: content)
        // The tray adds the home-indicator inset itself, and SwiftUI applying it too measures it twice.
        hosting.safeAreaRegions = []
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        parent?.addChild(hosting)
        card.addSubview(hosting.view)
        hosting.didMove(toParent: parent)

        let fitted = hosting.sizeThatFits(
            in: CGSize(width: bounds.width - trayMargin * 2, height: .greatestFiniteMagnitude)
        ).height

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: card.topAnchor),
            hosting.view.heightAnchor.constraint(equalToConstant: fitted),
        ])

        current = hosting
        let ceiling = bounds.height - safeAreaInsets.top - trayBottomMargin - keyboardInset - .spacingXXL
        standingHeight = min(fitted, ceiling)
    }

    private func unmount(_ hosting: UIHostingController<AnyView>) {
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }

    @objc private func dismissFromBackground() {
        onBackgroundDismiss()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let travelled = gesture.translation(in: self).y

        switch gesture.state {
        case .changed:
            offset.constant = -(trayBottomMargin + keyboardInset) + max(0, travelled)
            dimming.alpha = 1 - (max(0, travelled) / max(height.constant, 1)) * 0.6
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).y
            if velocity > trayDismissVelocity || travelled > height.constant / 3 {
                onBackgroundDismiss()
            } else {
                offset.constant = -(trayBottomMargin + keyboardInset)
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
