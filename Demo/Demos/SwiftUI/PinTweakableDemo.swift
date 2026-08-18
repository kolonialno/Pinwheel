import SwiftUI
import Pinwheel

struct PinTweakableDemo: SwiftUI.View {
    @SwiftUI.State private var optionIndex = 0
    @SwiftUI.State private var isOn = false

    private let options = ["Option 1", "Option 2"]

    var body: some SwiftUI.View {
        PinLabel(summary)
            .multilineTextAlignment(.center)
            .padding(.spacing8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.primaryBackground)
            .pinwheelTweaks {
                PinwheelTweak("Option", options: options, selection: $optionIndex)
                PinwheelTweak("Option 3", description: "Toggle-backed option", isOn: $isOn)
            }
    }

    private var summary: String {
        "You chose \(options[optionIndex]), and Option 3 is \(isOn ? "on" : "off")."
    }
}
