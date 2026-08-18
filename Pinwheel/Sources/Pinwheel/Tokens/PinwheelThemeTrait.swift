import SwiftUI
import UIKit

public nonisolated struct PinwheelThemeTrait: UITraitDefinition {
    public static let defaultValue = PinwheelTheme.standard
    public static let affectsColorAppearance = true
}

nonisolated struct PinwheelThemeKey: EnvironmentKey {
    static let defaultValue = PinwheelTheme.standard
}

extension PinwheelThemeKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> PinwheelTheme {
        traitCollection[PinwheelThemeTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: PinwheelTheme) {
        mutableTraits[PinwheelThemeTrait.self] = value
    }
}

public extension EnvironmentValues {
    var pinwheelTheme: PinwheelTheme {
        get { self[PinwheelThemeKey.self] }
        set { self[PinwheelThemeKey.self] = newValue }
    }
}

nonisolated struct PinwheelSelectedThemeKey: PreferenceKey {
    static let defaultValue: PinwheelTheme? = nil

    static func reduce(value: inout PinwheelTheme?, nextValue: () -> PinwheelTheme?) {
        value = nextValue() ?? value
    }
}

public extension SwiftUI.View {
    /// Reports the theme the catalog is showing, so a host above it can carry that selection into
    /// chrome the catalog has no reach over — a second design system's trait, the app's own tint.
    func onPinwheelThemeChange(_ action: @escaping @MainActor (PinwheelTheme) -> Void) -> some SwiftUI.View {
        onPreferenceChange(PinwheelSelectedThemeKey.self) { theme in
            guard let theme else { return }
            MainActor.assumeIsolated { action(theme) }
        }
    }
}
