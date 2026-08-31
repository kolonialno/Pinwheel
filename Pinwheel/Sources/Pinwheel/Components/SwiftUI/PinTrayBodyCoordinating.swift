import CoreGraphics

@MainActor
protocol PinTrayBodyCoordinating: AnyObject {
    var cardIsBeingDraggedDown: Bool { get }
    func bodyWillBeginDragging()
    func bodyDragged(by amount: CGFloat)
    func bodyEndedDragging(withVelocity velocity: CGFloat)
}

@MainActor
final class PinTrayBodyReports: PinTrayBodyCoordinating {
    private(set) var drags: [CGFloat] = []
    private(set) var releases: [CGFloat] = []
    var cardIsBeingDraggedDown = false

    func bodyWillBeginDragging() {}
    func bodyDragged(by amount: CGFloat) { drags.append(amount) }
    func bodyEndedDragging(withVelocity velocity: CGFloat) { releases.append(velocity) }
}
