import CoreGraphics

@MainActor
protocol PinTrayCardReporting: AnyObject {
    var pulledSoFar: CGFloat { get }
    func cardWasCaught(at travelled: CGFloat)
    func cardWasDragged(to travelled: CGFloat)
    func cardWasReleased(velocity: CGFloat)
}
