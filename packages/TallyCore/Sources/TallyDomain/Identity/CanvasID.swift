/// A Canvas identifier, typed by the entity it identifies.
///
/// Canvas IDs are 64-bit and are requested as strings
/// (`Accept: application/json+canvas-string-ids`), so values above 2^53
/// survive exactly. `Entity` is a phantom type: `CanvasID<Course>` and
/// `CanvasID<Assignment>` cannot be mixed up.
public struct CanvasID<Entity>: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Numeric order for Canvas's decimal IDs (shorter is smaller), then text order.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.rawValue.count != rhs.rawValue.count { return lhs.rawValue.count < rhs.rawValue.count }
        return lhs.rawValue < rhs.rawValue
    }
    public var description: String { rawValue }
}

extension CanvasID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(value) }
}

/// Dictionaries keyed by `CanvasID` encode as JSON objects (`{"51845": ...}`).
extension CanvasID: CodingKeyRepresentable {
    public var codingKey: any CodingKey { AnyKey(rawValue) }
    public init?<T: CodingKey>(codingKey: T) { self.init(codingKey.stringValue) }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}
