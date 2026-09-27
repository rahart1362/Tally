import Testing
import TallyDomain
@testable import TallyFeatures

/// UX-WP-10. Driven entirely through a fake `FirstSyncPublishing` — the real
/// `RefreshCoordinator` conformance is the app-core team's work package, so
/// this only tests `FirstSyncViewModel`'s own logic: phase bookkeeping,
/// progress, and the 10 s "large course loads" notice.
@MainActor
@Suite("First-sync skeleton (UX-WP-10)")
struct FirstSyncViewModelTests {
    @Test("Phases complete in order and the status text tracks them")
    func phasesCompleteInOrder() async {
        let publisher = FakeFirstSyncPublisher(events: [
            .phaseCompleted(.profileAndCourses), .phaseCompleted(.grades),
            .phaseCompleted(.dueItems), .phaseCompleted(.calendar), .finished,
        ])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield State University", publisher: publisher)
        #expect(viewModel.statusText == "Connecting to Northfield State University…")

        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.completedPhases == FirstSyncPhase.allCases)
        #expect(viewModel.isFinished)
        #expect(viewModel.progress == 1)
    }

    @Test("A duplicate phase event is not double-counted")
    func duplicatePhaseIsIgnored() async {
        let publisher = FakeFirstSyncPublisher(events: [
            .phaseCompleted(.profileAndCourses), .phaseCompleted(.profileAndCourses),
        ])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(viewModel.completedPhases == [.profileAndCourses])
    }

    @Test("A failure is reported and never overwritten by a later slow-load notice")
    func failureIsReported() async {
        let publisher = FakeFirstSyncPublisher(events: [.failed(.offline)])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(20))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(viewModel.failure == .offline)
        #expect(!viewModel.showsSlowLoadNotice)
    }

    @Test("Past the slow-load threshold with nothing finished, the notice appears")
    func slowLoadNoticeAppearsWhenNothingHasFinished() async {
        let publisher = FakeFirstSyncPublisher(events: []) // never emits
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(20))
        #expect(!viewModel.showsSlowLoadNotice)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(viewModel.showsSlowLoadNotice)
    }

    @Test("Finishing before the slow-load threshold suppresses the notice")
    func fastFinishSuppressesSlowLoadNotice() async {
        let publisher = FakeFirstSyncPublisher(events: [
            .phaseCompleted(.profileAndCourses), .phaseCompleted(.grades),
            .phaseCompleted(.dueItems), .phaseCompleted(.calendar), .finished,
        ])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(30))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.isFinished)
        #expect(!viewModel.showsSlowLoadNotice)
    }
}

private struct FakeFirstSyncPublisher: FirstSyncPublishing {
    let events: [FirstSyncEvent]

    func events() -> AsyncStream<FirstSyncEvent> {
        let events = self.events
        return AsyncStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
