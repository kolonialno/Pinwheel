import CoreGraphics

/// What the card tells whoever coordinates it, in its own words: a finger landed on it while it was
/// still travelling, it was dragged this far, it was let go at this speed.
@MainActor
protocol PinTrayCardReporting: AnyObject {
    /// How far the card has been pulled so far, so a gesture landing on it carries on from there.
    var pulledSoFar: CGFloat { get }
    func cardWasCaught(at travelled: CGFloat)
    func cardWasDragged(to travelled: CGFloat)
    func cardWasReleased(velocity: CGFloat)
}
