import CoreGraphics

@MainActor
protocol PinTrayCardReporting: AnyObject {
    /// Where a gesture landing on the card carries on from.
    var pulledSoFar: CGFloat { get }
    func cardWasCaught(at travelled: CGFloat)
    func cardWasDragged(to travelled: CGFloat)
    func cardWasReleased(velocity: CGFloat)
}
