import Synchronization
import Testing
import TallyDomain
@testable import TallyFeatures

/// UX-WP-10. Driven entirely through a fake `FirstSyncPublishing` (the real
/// `CoordinatorFirstSyncPublisher` is covered by `SignInFirstSyncTests`), so
/// this only tests `FirstSyncViewModel`'s own logic: phase bookkeeping,
/// progress, the 10 s "large course loads" notice, and (plan 06 step 9) that
/// nothing starts before `start()` and nothing keeps the model alive.
@MainActor
@Suite("First-sync skeleton (UX-WP-10)")
struct FirstSyncViewModelTests {
    @Test("Phases complete in order and the status text tracks them")
    func phasesCompleteInOrder() async throws {
        let publisher = FakeFirstSyncPublisher(events: [
            .phaseCompleted(.profileAndCourses), .phaseCompleted(.grades),
            .phaseCompleted(.dueItems), .phaseCompleted(.calendar), .finished,
        ])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield State University", publisher: publisher)
        viewModel.start()
        #expect(viewModel.statusText == "Connecting to Northfield State University…")

        // Waits for the events, not a fixed time: under ThreadSanitizer 100 ms was not enough
        // (run 36410352867's ios-tsan saw only the first phase).
        #expect(try await HomeTestSupport.waitUntil { viewModel.isFinished })
        #expect(viewModel.completedPhases == FirstSyncPhase.allCases)
        #expect(viewModel.isFinished)
        #expect(viewModel.progress == 1)
    }

    @Test("A duplicate phase event is not double-counted")
    func duplicatePhaseIsIgnored() async throws {
        // `.grades` after the duplicate: events arrive in order, so once it is in, the duplicate
        // has been handled too (a fixed 60 ms sleep could check before either had arrived).
        let publisher = FakeFirstSyncPublisher(events: [
            .phaseCompleted(.profileAndCourses), .phaseCompleted(.profileAndCourses), .phaseCompleted(.grades),
        ])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher)
        viewModel.start()
        #expect(try await HomeTestSupport.waitUntil { viewModel.completedPhases.contains(.grades) })
        #expect(viewModel.completedPhases == [.profileAndCourses, .grades])
    }

    @Test("A failure is reported and never overwritten by a later slow-load notice")
    func failureIsReported() async {
        let publisher = FakeFirstSyncPublisher(events: [.failed(.offline)])
        // The event is delivered at once; the threshold is far enough out that a busy main actor
        // cannot let the timer win (a 20 ms threshold flaked under parallel load).
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(500))
        viewModel.start()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(viewModel.failure == .offline)
        #expect(!viewModel.showsSlowLoadNotice)
    }

    @Test("Past the slow-load threshold with nothing finished, the notice appears")
    func slowLoadNoticeAppearsWhenNothingHasFinished() async {
        let publisher = FakeFirstSyncPublisher(events: []) // never emits
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(20))
        viewModel.start()
        #expect(!viewModel.showsSlowLoadNotice)
        try? await Task.sleep(for: .milliseconds(500)) // well past the 20 ms threshold
        #expect(viewModel.showsSlowLoadNotice)
    }

    @Test("Finishing before the slow-load threshold suppresses the notice")
    func fastFinishSuppressesSlowLoadNotice() async {
        let publisher = FakeFirstSyncPublisher(events: [
            .phaseCompleted(.profileAndCourses), .phaseCompleted(.grades),
            .phaseCompleted(.dueItems), .phaseCompleted(.calendar), .finished,
        ])
        // As above: the finish arrives at once, far ahead of the threshold (30 ms flaked 3 in 5
        // under parallel load on the Linux harness).
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(500))
        viewModel.start()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(viewModel.isFinished)
        #expect(!viewModel.showsSlowLoadNotice)
    }
}

extension FirstSyncViewModelTests {
    @Test("Nothing starts in init: no events are consumed before start()")
    func nothingStartsBeforeStart() async throws {
        let publisher = FakeFirstSyncPublisher(events: [.phaseCompleted(.profileAndCourses), .finished])
        let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield", publisher: publisher,
                                           slowLoadThreshold: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel.completedPhases.isEmpty)
        #expect(!viewModel.isFinished)
        #expect(!viewModel.showsSlowLoadNotice, "the slow-load timer ran without start()")
        viewModel.start()
        #expect(try await HomeTestSupport.waitUntil { viewModel.isFinished })
    }

    @Test("A started model is released once nothing holds it (its tasks hold it weakly)")
    func startedModelIsReleased() async throws {
        weak var released: FirstSyncViewModel?
        do {
            let viewModel = FirstSyncViewModel(schoolDisplayName: "Northfield",
                                               publisher: HangingFirstSyncPublisher(), // never emits, never finishes
                                               slowLoadThreshold: .seconds(60))
            viewModel.start()
            released = viewModel
            #expect(released != nil)
        }
        #expect(try await HomeTestSupport.waitUntil { released == nil }, "a running first-sync model outlived its owner")
    }
}

/// A publisher whose streams never emit and never finish (a first sync that hangs).
private final class HangingFirstSyncPublisher: FirstSyncPublishing {
    private let continuations = Mutex<[AsyncStream<FirstSyncEvent>.Continuation]>([])

    func events() -> AsyncStream<FirstSyncEvent> {
        let (stream, continuation) = AsyncStream<FirstSyncEvent>.makeStream()
        continuations.withLock { $0.append(continuation) }
        return stream
    }
}

private struct FakeFirstSyncPublisher: FirstSyncPublishing {
    let queuedEvents: [FirstSyncEvent]

    init(events: [FirstSyncEvent]) {
        queuedEvents = events
    }

    func events() -> AsyncStream<FirstSyncEvent> {
        let queuedEvents = self.queuedEvents
        return AsyncStream { continuation in
            Task {
                for event in queuedEvents {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
