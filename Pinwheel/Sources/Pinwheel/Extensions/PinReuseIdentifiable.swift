import Foundation

public protocol PinReuseIdentifiable {
    static var reuseIdentifier: String { get }
}

public extension PinReuseIdentifiable {
    static var reuseIdentifier: String {
        return String(describing: self)
    }
}
