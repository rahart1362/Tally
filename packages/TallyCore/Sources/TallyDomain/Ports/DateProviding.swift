import Foundation

/// Source of "now". Injected everywhere time matters so tests are deterministic.
/// (Named to avoid clashing with the standard library's `Clock` protocol.)
public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
}
