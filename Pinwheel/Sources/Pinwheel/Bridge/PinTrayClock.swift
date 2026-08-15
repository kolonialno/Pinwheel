import Foundation

/// The one thing the tray needs from time: somewhere to put work that happens later. A wait for a
/// keyboard that may never speak, and the pause before a leaving tray is torn down, are both real
/// delays in the app and both instant in a test.
@MainActor
protocol PinTrayClock {
    func after(_ delay: TimeInterval, _ work: @escaping () -> Void)
}

/// The real one.
@MainActor
struct PinTrayMainClock: PinTrayClock {
    func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// The stub. Nothing fires until a test says so, and it records what was asked for.
@MainActor
final class PinTrayHeldClock: PinTrayClock {
    private(set) var pending: [(delay: TimeInterval, work: () -> Void)] = []

    func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        pending.append((delay, work))
    }

    /// Runs everything waiting, and anything that scheduling those adds.
    func advance() {
        while !pending.isEmpty {
            let due = pending
            pending = []
            due.forEach { $0.work() }
        }
    }
}
