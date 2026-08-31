import Foundation

extension String {
    nonisolated var pinwheelGeneratedID: String {
        let allowed = CharacterSet.alphanumerics
        let scalars = unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(String(scalar).lowercased())
            } else {
                return "-"
            }
        }

        let dashed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")

        if !dashed.isEmpty { return dashed }
        let hex = unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
        return hex.isEmpty ? "untitled" : hex
    }
}
