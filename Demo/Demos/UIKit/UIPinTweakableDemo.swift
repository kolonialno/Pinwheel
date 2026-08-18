import UIKit
import Pinwheel

class UIPinTweakableDemo: UIPinView, Tweakable {
    private let options = ["Option 1", "Option 2"]
    private var optionIndex = 0
    private var isOn = false

    lazy var tweaks: [Tweak] = {
        return [
            SelectTweak(
                title: "Option",
                options: options,
                chosenOption: { self.optionIndex },
                action: { self.optionIndex = $0; self.reload() }
            ),
            BoolTweak(title: "Option 3", description: "Toggle-backed option") { isOn in
                self.isOn = isOn
                self.reload()
            }
        ]
    }()

    lazy var titleLabel: UIPinLabel = {
        let label = UIPinLabel(font: .body)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    // A centered stack (not a bare fill-pinned label) so the capture reads it as an auto-layout column,
    // matching the SwiftUI demo in every state — the tweaks only swap the label's text.
    override func setup() {
        let stack = UIStackView(arrangedSubviews: [titleLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: .spacing8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.spacing8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        reload()
    }

    private func reload() {
        titleLabel.text = "You chose \(options[optionIndex]), and Option 3 is \(isOn ? "on" : "off")."
    }
}
