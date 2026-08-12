import SwiftUI

/// The silhouette a theme gives its buttons. A capsule is half the button's height rather than a
/// fixed radius, so it stays a shape here instead of collapsing to a `CGFloat`.
public enum PinButtonShape: Sendable, Equatable {
    case rounded
    case capsule

    var shape: AnyShape {
        switch self {
        case .rounded:
            return AnyShape(RoundedRectangle(cornerRadius: .spacingM, style: .continuous))
        case .capsule:
            return AnyShape(Capsule(style: .continuous))
        }
    }
}
