import UIKit
import SwiftUI

public struct PinwheelSelection: Hashable, Identifiable {
    public let sectionID: String
    public let itemID: String

    public var id: String {
        return "\(sectionID)/\(itemID)"
    }

    public init(sectionID: String, itemID: String) {
        self.sectionID = sectionID
        self.itemID = itemID
    }
}
