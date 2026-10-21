import Foundation

/// SEC1-16: a `[Element]` that never fails to decode because of one malformed element. Canvas
/// array responses were decoded with `decoder.decode([Element].self, ...)` in one call, so a
/// single row whose shape didn't match `Element` (an unexpected type, a field renamed server-
/// side) threw for the *whole* page -- even though every other row decoded fine. This gives the
/// same "skip and count" contract a caller already gets for a structurally valid row that is
/// semantically incomplete (`PlannerItemMapper`'s `compactMap`, `PlannerItemDTO.swift:63-70`), one
/// level earlier, at the JSON shape itself.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    let dropped: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var dropped = 0
        while !container.isAtEnd {
            if let element = try container.decode(Safe<Element>.self).value {
                elements.append(element)
            } else {
                dropped += 1
            }
        }
        self.elements = elements
        self.dropped = dropped
    }

    /// Decodes `Value`, turning any decoding error on *this one element* into `nil` instead of
    /// letting it propagate. `Safe.init` itself never throws, so the outer unkeyed container's
    /// `decode(_:)` call never throws either, and its cursor still advances past the malformed
    /// element -- the trick that makes the loop above skip one bad row rather than abort the
    /// whole array.
    private struct Safe<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}
