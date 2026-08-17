import SwiftUI
import UIKit

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

    func makeCoordinator() -> PinTraySync<Item> {
        PinTraySync()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismissAll = { path.removeAll() }
        coordinator.exit = { path = PinTraySync<Item>.exited(path) }
        coordinator.sync(path: path, from: controller, tray: content)
    }
}
