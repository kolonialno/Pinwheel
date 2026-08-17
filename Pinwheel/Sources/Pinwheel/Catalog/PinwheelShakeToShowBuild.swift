import SwiftUI
import UIKit

/// A shake anywhere in the catalog says which build is running, so a handover can be checked rather than
/// trusted. iOS delivers a shake to the first responder, which is why this controller takes it.
struct PinwheelShakeToShowBuild: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeController { ShakeController() }

    func updateUIViewController(_ controller: ShakeController, context: Context) {}

    final class ShakeController: UIViewController {
        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else { return }
            let alert = UIAlertController(
                title: PinwheelBuild.label,
                message: PinwheelBuild.detail,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            (view.window?.rootViewController ?? self).topmost.present(alert, animated: true)
        }
    }
}

private extension UIViewController {
    var topmost: UIViewController {
        presentedViewController?.topmost ?? self
    }
}
