import CoreGraphics

@MainActor
protocol PinTrayCardReporting: AnyObject {
    var dragInProgress: CGFloat { get }
    func cardWillBeginDragging()
    func cardDragged(to drag: CGFloat)
    func cardEndedDragging(withVelocity velocity: CGFloat)
}

@MainActor
final class PinTrayCardReports: PinTrayCardReporting {
    private(set) var drags: [CGFloat] = []
    private(set) var releases: [CGFloat] = []
    var dragInProgress: CGFloat = 0

    func cardWillBeginDragging() {}
    func cardDragged(to drag: CGFloat) { drags.append(drag) }
    func cardEndedDragging(withVelocity velocity: CGFloat) { releases.append(velocity) }
}
