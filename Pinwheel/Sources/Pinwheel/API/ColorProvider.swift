import UIKit

/// Token lookups are pure, so they stay off the main actor — a themed `UIColor` resolves them
/// from inside a `@Sendable` dynamic-provider closure.
public nonisolated protocol ColorProvider: Sendable {
    var primaryText: UIColor { get }
    var secondaryText: UIColor { get }
    var tertiaryText: UIColor { get }
    var actionText: UIColor { get }
    var criticalText: UIColor { get }

    var primaryBackground: UIColor { get }
    var secondaryBackground: UIColor { get }
    var actionBackground: UIColor { get }
    var criticalBackground: UIColor { get }
}
