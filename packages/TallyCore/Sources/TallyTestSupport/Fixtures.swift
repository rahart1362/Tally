import Foundation

/// Reads the synthetic Canvas fixtures at `<repo>/fixtures/canvas` (tools/canvas-synth).
public enum Fixtures {
    public static func root(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")               // .../packages/TallyCore/Sources/TallyTestSupport/Fixtures.swift
            .deletingLastPathComponent()               // TallyTestSupport
            .deletingLastPathComponent()               // Sources
            .deletingLastPathComponent()               // TallyCore
            .deletingLastPathComponent()               // packages
            .deletingLastPathComponent()               // repo root
            .appendingPathComponent("fixtures/canvas")
    }

    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root().appendingPathComponent(relativePath))
    }

    public static let personas = ["flagship", "flagship-previous", "finals", "grading-periods", "empty", "large"]
}
