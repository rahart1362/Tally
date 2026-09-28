// PERF-05 PA-6 (docs/pmo/reviews/perf-algorithms.md): what `CanvasDate.parse` costs inside the
// stress-scale mapper decode (`mapperDecode/stress`), measured over the exact date strings that
// decode parses: every non-null `Date` field the stress transport's courses and
// assignment-groups bodies carry. A JSON `null` never reaches the date strategy.
//
// An `extension CoreBenchmarks`, for the reason `ScalingGateTests.swift` gives.
#if !DEBUG
import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    /// The `Date`-typed keys of `CourseDTO.TermDTO` and `AssignmentGroupDTO`'s assignment and
    /// submission DTOs, the only dates `mapperDecode` decodes.
    private static let mapperDateKeys: Set<String> = ["start_at", "end_at", "due_at", "lock_at", "submitted_at", "graded_at", "posted_at"]

    private static func dateStrings(in json: Any, into out: inout [String]) {
        if let object = json as? [String: Any] {
            for key in object.keys.sorted() {
                guard let value = object[key] else { continue }
                if Self.mapperDateKeys.contains(key), let text = value as? String { out.append(text) } else { dateStrings(in: value, into: &out) }
            }
        } else if let array = json as? [Any] {
            for element in array { dateStrings(in: element, into: &out) }
        }
    }

    @Test func canvasDateParseShareOfMapperDecode() async throws {
        let context = try await PerfFixtures.context(for: .stress)
        let bodies = try loadMapperBodies(for: .stress, context: context)
        var strings: [String] = []
        for body in [bodies.coursesBody] + bodies.perCourse.map(\.body) {
            Self.dateStrings(in: try JSONSerialization.jsonObject(with: body), into: &strings)
        }
        #expect(strings.count > 10_000, "only \(strings.count) date strings")
        #expect(strings.allSatisfy { CanvasDate.parse($0) != nil }, "every stress date string must parse")
        print("PERF-SIZE | canvasDateParse/stress | dateStrings=\(strings.count)")

        let (decode, parse) = try Bench.timeInterleaved(
            "mapperDecode/stress/forDateShare", "canvasDateParse/stress", iterations: 11, warmup: 2,
            {
                _ = try CourseMapper.map(bodies.coursesBody, host: bodies.host)
                for (courseID, body) in bodies.perCourse { _ = try AssignmentGroupMapper.map(body, courseID: courseID) }
            },
            {
                var checksum = 0.0
                for text in strings { checksum += CanvasDate.parse(text)?.timeIntervalSince1970 ?? 0 }
                Bench.keep(checksum)
            })
        let ms: (Duration) -> Double = { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }
        let perCallNs = ms(parse.median) * 1e6 / Double(strings.count)
        print("PERF-SHARE | mapperDecode/stress | CanvasDate.parse = \(String(format: "%.2f", ms(parse.median)))ms of "
            + "\(String(format: "%.2f", ms(decode.median)))ms (\(String(format: "%.0f", 100 * ms(parse.median) / ms(decode.median)))%), "
            + "\(String(format: "%.0f", perCallNs))ns per date")
    }
}
#endif
