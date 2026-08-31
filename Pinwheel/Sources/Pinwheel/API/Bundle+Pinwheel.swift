import Foundation

public extension Bundle {
    static var pinwheel: Bundle {
        return Bundle(for: UIPinTableViewCell.self)
    }
}
