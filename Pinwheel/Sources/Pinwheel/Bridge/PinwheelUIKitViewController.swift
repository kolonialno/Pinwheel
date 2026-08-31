import SwiftUI
import UIKit

public struct PinwheelUIKitViewController: UIViewControllerRepresentable {
    private let makeViewController: () -> UIViewController

    public init(makeViewController: @escaping () -> UIViewController) {
        self.makeViewController = makeViewController
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        return makeViewController()
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
