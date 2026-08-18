import SwiftUI
import UIKit
import Pinwheel

@main
struct DemoApp: App {
    init() {
        // -PinwheelPreview lives in the argument domain, so it survives the clear.
        if ProcessInfo.processInfo.arguments.contains("-UITestingNoAnimations") {
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
            UIView.setAnimationsEnabled(false)
        }

        PinwheelRecorder.start()

        if FigmaCatalog.isManifestDump {
            FigmaCatalog.dumpManifest()
        }

    }

    /// A UIAlertController and anything else the system presents draws in the app window's tint, which
    /// no catalog window reaches.
    private func tintTheApp(_ theme: PinwheelTheme) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.tintColor = theme.colors.actionText
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let captureID = FigmaCatalog.requestedCaptureID {
                FigmaCaptureSweepView(id: captureID)
            } else if let previewID = PinwheelPreview.requestedID {
                PinwheelPreview(previewID, sections: DemoPinwheelSections.all, themes: DemoThemes.all)
                    .onPinwheelThemeChange(tintTheApp)
            } else {
                PinwheelCatalog(themes: DemoThemes.all) {
                    DemoPinwheelSections.all
                }
                .environment(\.pinCaptureSink) { FigmaCatalog.autoPush(id: $0) }
                .onPinwheelThemeChange(tintTheApp)
            }
        }
    }
}
