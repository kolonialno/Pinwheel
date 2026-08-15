import UIKit

/// Whether focusing a field will actually raise a keyboard.
///
/// A tray that is about to raise one holds still until it moves, so that a shrinking card does not drop
/// to the floor and climb back. That hold is only correct when a keyboard is coming: with a hardware
/// keyboard attached the field takes focus and nothing ever rises, and a tray that waits for it waits
/// for ever. The alternative was a stopwatch on the wait, which is a guess about the world dressed as
/// a timeout.
///
/// GraphicsServices answers it outright, so the question is asked rather than estimated. It is private,
/// looked up by name, and absent means no hardware keyboard — the same answer the simulator gives with
/// one disconnected.
enum PinTrayKeyboardPresence {
    private static let hardwareKeyboardIsAttached: () -> Bool = {
        typealias IsAttached = @convention(c) () -> Bool
        guard
            let services = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY),
            let symbol = dlsym(services, "GSEventIsHardwareKeyboardAttached")
        else {
            return { false }
        }
        let isAttached = unsafeBitCast(symbol, to: IsAttached.self)
        return isAttached
    }()

    /// True when focusing something would put a keyboard on screen.
    static var aKeyboardWouldAppear: Bool {
        !hardwareKeyboardIsAttached()
    }
}
