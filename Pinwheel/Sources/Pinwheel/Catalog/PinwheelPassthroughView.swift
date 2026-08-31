import SwiftUI
import UIKit

final class PinwheelPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in subviews where !subview.isHidden && subview.isUserInteractionEnabled && subview.alpha > 0.01 {
            if subview.point(inside: convert(point, to: subview), with: event) {
                return true
            }
        }
        return false
    }
}
