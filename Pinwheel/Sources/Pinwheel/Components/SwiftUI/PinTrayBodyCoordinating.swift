import CoreGraphics

/// What a tray's body tells whoever coordinates it, in its own words.
///
/// Deliberately not `UIScrollViewDelegate`: the body answers to that itself, and what travels upward is
/// what happened to the tray — it was pulled with nothing left to scroll, and then let go. Nothing above
/// the body needs to know a scroll view exists.
@MainActor
protocol PinTrayBodyCoordinating: AnyObject {
    /// A drag is starting. Whoever is coordinating stops whatever the card was doing and answers how
    /// far down it already is, so a pull that lands on a moving tray carries on from where it got to.
    func bodyWillBeginPulling() -> CGFloat
    /// Pulled downward with nothing above the first row to reveal.
    func bodyWasPulledDown(by amount: CGFloat)
    /// That pull ended. Positive velocity is downward.
    func bodyStoppedBeingPulled(velocity: CGFloat)
}

/// The stub. A body works with nothing above it, and a test can read back what it said.
@MainActor
final class PinTrayBodyReports: PinTrayBodyCoordinating {
    private(set) var pulls: [CGFloat] = []
    private(set) var releases: [CGFloat] = []
    /// Where a caught tray already stood. Nought unless a test says otherwise.
    var standing: CGFloat = 0

    func bodyWillBeginPulling() -> CGFloat { standing }
    func bodyWasPulledDown(by amount: CGFloat) { pulls.append(amount) }
    func bodyStoppedBeingPulled(velocity: CGFloat) { releases.append(velocity) }
}
