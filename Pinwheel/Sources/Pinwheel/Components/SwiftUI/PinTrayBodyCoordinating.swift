import CoreGraphics

@MainActor
protocol PinTrayBodyCoordinating: AnyObject {
    func bodyWillBeginPulling() -> CGFloat
    func bodyWasPulledDown(by amount: CGFloat)
    func bodyStoppedBeingPulled(velocity: CGFloat)
}

@MainActor
final class PinTrayBodyReports: PinTrayBodyCoordinating {
    private(set) var pulls: [CGFloat] = []
    private(set) var releases: [CGFloat] = []
    var standing: CGFloat = 0

    func bodyWillBeginPulling() -> CGFloat { standing }
    func bodyWasPulledDown(by amount: CGFloat) { pulls.append(amount) }
    func bodyStoppedBeingPulled(velocity: CGFloat) { releases.append(velocity) }
}
