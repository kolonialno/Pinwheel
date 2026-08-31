import CoreGraphics

@MainActor
protocol PinTrayCardReporting: AnyObject {
    var dragInProgress: CGFloat { get }
    func cardWillBeginDragging()
    func cardDragged(to drag: CGFloat)
    func cardEndedDragging(withVelocity velocity: CGFloat)
}
