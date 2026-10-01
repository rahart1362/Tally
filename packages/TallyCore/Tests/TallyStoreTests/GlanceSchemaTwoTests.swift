import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// Plan 08 XG-02, §4.4 rows 14-15: glance schema 2. The grade summary the Standing widget reads,
/// one exclusion rule with the dashboard hero, a status per course, and the schema-1 read path.
@Suite("Glance schema 2: grade summary, per-course status, one exclusion rule, schema-1 files")
struct GlanceSchemaTwoTests {
    /// The `external-grades` persona's anchor, 2026-09-28T13:00:00Z.
    static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    static func persona(_ name: String = "external-grades") async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: name, now: anchor)
    }

    /// `snapshot` with only the courses whose code is in `codes`, at `generation`.
    static func trimmed(_ snapshot: CanvasSnapshot, keeping codes: Set<String>? = nil,
                        generation: UInt64? = nil) -> CanvasSnapshot {
        let courses = snapshot.courses.filter { codes?.contains($0.courseCode) ?? true }
        let ids = Set(courses.map(\.id))
        return CanvasSnapshot(
            generation: generation ?? snapshot.generation, accountKey: snapshot.accountKey, host: snapshot.host,
            fetchedAt: snapshot.fetchedAt, profile: snapshot.profile, courses: courses,
            groups: snapshot.groups.filter { ids.contains($0.key) },
            gradingPeriods: snapshot.gradingPeriods.filter { ids.contains($0.key) }, planner: snapshot.planner,
            events: snapshot.events, announcements: snapshot.announcements, courseColors: snapshot.courseColors,
            sections: snapshot.sections)
    }

    static let noneInCanvas: Set<String> = ["ENG-10", "ALG2", "BIO-H", "ART-1", "ADVISORY"]

    static func byCode<T>(_ glance: GlanceProjection, _ value: (GlanceCourse) -> T) -> [String: T] {
        Dictionary(uniqueKeysWithValues: glance.courses.map { ($0.shortCode, value($0)) })
    }

    // MARK: - Row 14: the grade summary

    @Test("external-grades, opted in: the band of SPAN-2 alone; a status per course; a band only for SPAN-2")
    func personaOptedIn() async throws {
        let glance = GlanceProjectionBuilder.build(from: try await Self.persona(), includeGrades: true)
        #expect(glance.gradeSummary == .band(.aRange))
        #expect(glance.overallGradeBand == .aRange)
        #expect(Self.byCode(glance, \.gradeStatus) == [
            "ENG-10": .keptOutsideCanvas, "ALG2": .keptOutsideCanvas, "BIO-H": .keptOutsideCanvas,
            "ART-1": .notYetPosted, "ADVISORY": .notGradedInCanvas, "SPAN-2": .averaged,
        ])
        #expect(Self.byCode(glance, \.currentGrade) == [
            "ENG-10": nil, "ALG2": nil, "BIO-H": nil, "ART-1": nil, "ADVISORY": nil, "SPAN-2": .aRange,
        ])
    }

    @Test("Not opted in: notOptedIn whatever the grades are, no band anywhere; the statuses are still there")
    func notOptedIn() async throws {
        let persona = try await Self.persona()
        for snapshot in [persona, Self.trimmed(persona, keeping: Self.noneInCanvas)] {
            let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
            #expect(glance.gradeSummary == .notOptedIn)
            #expect(glance.overallGradeBand == nil)
            #expect(glance.courses.allSatisfy { $0.currentGrade == nil })
            #expect(glance.courses.allSatisfy { $0.gradeStatus != nil })
        }
    }

    @Test("Opted in with nothing averaged: notInCanvas for a noneInCanvas school, noneYet otherwise")
    func nothingAveraged() async throws {
        let persona = try await Self.persona()
        let none = GlanceProjectionBuilder.build(from: Self.trimmed(persona, keeping: Self.noneInCanvas), includeGrades: true)
        #expect(none.gradeSummary == .notInCanvas)
        let early = GlanceProjectionBuilder.build(from: Self.trimmed(persona, keeping: ["ART-1", "ADVISORY"]),
                                                  includeGrades: true)
        #expect(early.gradeSummary == .noneYet)
        let empty = GlanceProjectionBuilder.build(from: Self.trimmed(persona, keeping: []), includeGrades: true)
        #expect(empty.gradeSummary == .noneYet)
    }

    @Test("A student's override reaches the glance through the index it is built with")
    func overrideReachesTheGlance() async throws {
        let snapshot = try await Self.persona()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [spanish.id: .keptOutsideCanvas],
                                           now: snapshot.fetchedAt)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true, gradeAvailability: index)
        #expect(glance.gradeSummary == .notInCanvas)
        #expect(Self.byCode(glance, \.gradeStatus)["SPAN-2"] == .keptOutsideCanvas)
        #expect(Self.byCode(glance, \.currentGrade)["SPAN-2"] == .some(nil))
        // Without the index, the builder classifies the snapshot itself, at its fetch time, with no override.
        #expect(GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
                == GlanceProjectionBuilder.build(from: snapshot, includeGrades: true,
                                                 gradeAvailability: GradeAvailabilityIndex(
                                                    snapshot: snapshot, overrides: [:], now: snapshot.fetchedAt)))
    }

    // MARK: - Row 15: one exclusion rule with the dashboard hero

    @Test("The glance's band and averaged courses are the dashboard hero's, persona by persona",
          arguments: ["flagship", "flagship-previous", "finals", "grading-periods", "large", "external-grades"])
    func oneRuleWithTheHero(persona: String) async throws {
        let snapshot = try await Self.persona(persona)
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: snapshot.fetchedAt)
        let hero = DashboardBuilder.hero(courses: snapshot.courses, gradeAvailability: index)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true, gradeAvailability: index)
        #expect(glance.overallGradeBand == hero.overallBand)
        #expect(glance.courses.filter { $0.gradeStatus == .averaged }.count == hero.averagedCount)
        #expect(glance.courses.map(\.gradeStatus) == snapshot.courses.map {
            CourseGradeStatus(course: $0, availability: index[$0.id])
        })
    }

    @Test("Row 2: the launch paint's hero from the glance is the full projection's, but for the percentage",
          arguments: ["flagship", "grading-periods", "large", "external-grades", "external-grades/noneInCanvas"])
    func launchHeroMatchesTheFullHero(persona: String) async throws {
        let full = try await Self.persona(String(persona.prefix { $0 != "/" }))
        let snapshot = persona.hasSuffix("/noneInCanvas") ? Self.trimmed(full, keeping: Self.noneInCanvas) : full
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: snapshot.fetchedAt)
        let projected = DashboardBuilder.hero(courses: snapshot.courses, gradeAvailability: index)
        for includeGrades in [false, true] {
            let launch = GlanceProjectionBuilder.build(from: snapshot, includeGrades: includeGrades, gradeAvailability: index).hero
            #expect(launch.courseCount == projected.courseCount)
            #expect(launch.averagedCount == projected.averagedCount)
            #expect(launch.exclusions == projected.exclusions)
            #expect(launch.school == projected.school)
            #expect(launch.overallPercent == nil, "the glance carries no percentage (D-P1)")
            #expect(launch.overallBand == (includeGrades ? projected.overallBand : nil))
        }
        if persona == "flagship" {
            #expect(projected.averagedCount == 5, "the launch paint still reads 'Average of 5 courses'")
        }
    }

    @Test("Row 2: a repeated course counts once; a schema-1 glance counts every course, as it used to")
    func launchHeroEdges() throws {
        let repeated = GlanceProjection(generation: 1, asOf: Self.anchor, gradeSummary: .noneYet, courses: [
            GlanceCourse(id: "1", shortCode: "A", currentGrade: nil, gradeStatus: .keptOutsideCanvas),
            GlanceCourse(id: "1", shortCode: "A", currentGrade: nil, gradeStatus: .keptOutsideCanvas),
            GlanceCourse(id: "2", shortCode: "B", currentGrade: nil, gradeStatus: .averaged),
        ], dueSoon: [])
        #expect(repeated.hero == DashboardProjection.Hero(courseCount: 2, averagedCount: 1, overallPercent: nil,
                                                           overallBand: nil, exclusions: [.keptOutsideCanvas: 1],
                                                           school: .mixed(outside: 1)))
        let legacy = try JSONDecoder().decode(GlanceProjection.self,
                                              from: try Self.schemaOne(overall: .bRange, courseBands: [.aRange, nil, nil]))
        #expect(legacy.hero == DashboardProjection.Hero(courseCount: 3, averagedCount: 3, overallPercent: nil,
                                                         overallBand: .bRange, exclusions: [:], school: .undetermined))
    }

    @Test("A letters-only course's percent is no longer in the overall band (it never was in the hero's)")
    func lettersOnlyIsOutOfTheOverallBand() {
        func course(_ id: String, _ visibility: GradeVisibility, _ score: Double, _ grade: String) -> Course {
            Course(id: CanvasID(id), name: "Course \(id)", courseCode: "C\(id)", term: nil, teachers: [], timeZone: nil,
                   appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                   gradeVisibility: visibility,
                   scores: ComputedScores(currentScore: score, finalScore: score, currentGrade: grade, finalGrade: nil),
                   currentPeriodScores: nil, htmlURL: nil)
        }
        let base = CanvasSnapshotFixture.make(courseCount: 0, dueItemCount: 0)
        let snapshot = CanvasSnapshot(
            generation: 1, accountKey: base.accountKey, host: base.host, fetchedAt: base.fetchedAt, profile: base.profile,
            courses: [course("1", .visible, 95, "A"), course("2", .lettersOnly, 55, "F")], groups: [:],
            gradingPeriods: [:], planner: [], events: [], announcements: [], courseColors: [:], sections: base.sections)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
        // Schema 1 averaged 95 and 55 (75, a C); the hero, and now the glance, average 95 alone.
        #expect(glance.gradeSummary == .band(.aRange))
        #expect(glance.courses.map(\.gradeStatus) == [.averaged, .lettersOnly])
        #expect(glance.courses.map(\.currentGrade) == [.aRange, .fRange], "a letters-only course keeps its own band")
    }

    // MARK: - Schema 2 encoding

    @Test("Schema 2 is written, and every summary state round-trips with its documented encoding")
    func schemaTwoEncoding() throws {
        #expect(GlanceProjection.currentSchemaVersion == 2)
        let glance = GlanceProjectionBuilder.build(from: CanvasSnapshotFixture.make(), includeGrades: true)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(glance)) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 2)

        let cases: [(GlanceGradeSummary, String)] = [
            (.notOptedIn, #"{"state":"notOptedIn"}"#), (.band(.bRange), #"{"band":"b","state":"band"}"#),
            (.noneYet, #"{"state":"noneYet"}"#), (.notInCanvas, #"{"state":"notInCanvas"}"#),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for (summary, encoded) in cases {
            #expect(String(decoding: try encoder.encode(summary), as: UTF8.self) == encoded)
            #expect(try JSONDecoder().decode(GlanceGradeSummary.self, from: Data(encoded.utf8)) == summary)
        }
        for invalid in [#"{"state":"maybe"}"#, #"{"state":"band"}"#, #"{}"#] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(GlanceGradeSummary.self, from: Data(invalid.utf8)) }
        }
    }

    // MARK: - The schema-1 read path

    /// Schema 1's exact shape (`GlanceProjection.swift` @ 47a461c, synthesized `Codable`): the same
    /// property names and types, so the same bytes.
    struct SchemaOneGlance: Encodable {
        struct Course: Encodable {
            let id: CanvasID<TallyDomain.Course>
            let shortCode: String
            let currentGrade: GradeBand?
        }
        var schemaVersion = 1
        let generation: UInt64
        let asOf: Date
        let overallGradeBand: GradeBand?
        let courses: [Course]
        let dueSoon: [GlanceDueItem]
    }

    static func schemaOne(generation: UInt64 = 1, overall: GradeBand?, courseBands: [GradeBand?]) throws -> Data {
        try JSONEncoder().encode(SchemaOneGlance(
            generation: generation, asOf: anchor, overallGradeBand: overall,
            courses: courseBands.enumerated().map { .init(id: CanvasID("\(100 + $0)"), shortCode: "CRS\(100 + $0)", currentGrade: $1) },
            dueSoon: [GlanceDueItem(id: "assignment:1", courseShortCode: "CRS100", title: "Lab", dueAt: anchor,
                                    missing: false, late: false, excused: false, submitted: false)]))
    }

    @Test("A schema-1 glance still reads: its band becomes the summary, its courses have no status")
    func schemaOneDecodes() throws {
        let optedIn = try JSONDecoder().decode(GlanceProjection.self,
                                               from: try Self.schemaOne(generation: 7, overall: .bRange, courseBands: [.aRange, .cRange]))
        #expect(optedIn.schemaVersion == 1)
        #expect(optedIn.generation == 7)
        #expect(optedIn.asOf == Self.anchor)
        #expect(optedIn.gradeSummary == .band(.bRange))
        #expect(optedIn.courses.map(\.currentGrade) == [.aRange, .cRange])
        #expect(optedIn.courses.allSatisfy { $0.gradeStatus == nil })
        #expect(optedIn.dueSoon.map(\.title) == ["Lab"])

        let hidden = try JSONDecoder().decode(GlanceProjection.self, from: try Self.schemaOne(overall: nil, courseBands: [nil, nil]))
        #expect(hidden.gradeSummary == .notOptedIn)
        // Schema 1 wrote a course band only for an opted-in user: no overall band means no average yet.
        let courseOnly = try JSONDecoder().decode(GlanceProjection.self, from: try Self.schemaOne(overall: nil, courseBands: [nil, .aRange]))
        #expect(courseOnly.gradeSummary == .noneYet)
        // A schema-2 file without its summary is not a schema-1 file: it does not decode.
        var broken = try #require(try JSONSerialization.jsonObject(with: Self.schemaOne(overall: .aRange, courseBands: [])) as? [String: Any])
        broken["schemaVersion"] = 2
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GlanceProjection.self, from: JSONSerialization.data(withJSONObject: broken))
        }
    }

    private let accountKey = AccountKey("acct-glance-v2")

    private func sealer() -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
    }

    private func writeSealed(_ data: Data, _ file: StoreFile, root: URL, sealer: VaultSealer) throws {
        try ProtectedFile.atomicWrite(try sealer.seal(data, file: file),
                                      to: StoreLayout(root: root, accountKey: accountKey).url(for: file), excludeFromBackup: true)
    }

    @Test("A schema-1 glance on disk: the widget reads it as it is; the app's next snapshot load rebuilds it, keeping the opt-in",
          arguments: [true, false])
    func schemaOneOnDiskIsRebuilt(optedIn: Bool) async throws {
        let root = try tempStoreDirectory()
        let sealer = sealer()
        let owner = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
        let snapshot = CanvasSnapshotFixture.make(generation: 3, accountKey: accountKey)
        try await owner.commit(snapshot, includeGrades: !optedIn) // the opposite, so the rebuild has to carry it
        // What the previous app version left: a schema-1 glance for the same generation.
        try writeSealed(try Self.schemaOne(generation: 3, overall: optedIn ? .bRange : nil, courseBands: [nil, nil]),
                        .glance, root: root, sealer: sealer)

        let widget = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer, isOwner: false)
        guard case .loaded(let read) = await widget.loadGlance() else { Issue.record("the widget cannot read schema 1"); return }
        #expect(read.schemaVersion == 1)
        #expect(read.gradeSummary == (optedIn ? .band(.bRange) : .notOptedIn))
        _ = await widget.loadSnapshot()
        guard case .loaded(let untouched) = await widget.loadGlance() else { Issue.record("expected the glance"); return }
        #expect(untouched.schemaVersion == 1, "a non-owner never rewrites the glance")

        guard case .loaded = await owner.loadSnapshot() else { Issue.record("expected the snapshot"); return }
        guard case .loaded(let rebuilt) = await owner.loadGlance() else { Issue.record("expected a rebuilt glance"); return }
        #expect(rebuilt == GlanceProjectionBuilder.build(from: snapshot, includeGrades: optedIn))
        #expect(rebuilt.schemaVersion == 2)
        #expect(rebuilt.courses.allSatisfy { $0.gradeStatus == .averaged })
    }

    @Test("Self-heal keeps the opt-in of a student with nothing to average (the old reading lost it)")
    func selfHealKeepsAnOptInWithoutABand() async throws {
        let root = try tempStoreDirectory()
        let sealer = sealer()
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
        let persona = try await Self.persona()
        try await store.commit(Self.trimmed(persona, keeping: Self.noneInCanvas, generation: 1), includeGrades: true)
        guard case .loaded(let committed) = await store.loadGlance() else { Issue.record("expected a glance"); return }
        #expect(committed.gradeSummary == .notInCanvas)
        #expect(committed.overallGradeBand == nil && committed.courses.allSatisfy { $0.currentGrade == nil })

        // A crash between the two writes of the next commit: the snapshot is at generation 2, the glance at 1.
        let next = Self.trimmed(persona, keeping: Self.noneInCanvas, generation: 2)
        try writeSealed(try JSONEncoder().encode(next), .snapshot, root: root, sealer: sealer)
        guard case .loaded = await store.loadSnapshot() else { Issue.record("expected the snapshot"); return }
        guard case .loaded(let healed) = await store.loadGlance() else { Issue.record("expected the healed glance"); return }
        #expect(healed.generation == 2)
        #expect(healed.gradeSummary == .notInCanvas, "still opted in: the widget must not say 'choose to show grades'")
    }
}
