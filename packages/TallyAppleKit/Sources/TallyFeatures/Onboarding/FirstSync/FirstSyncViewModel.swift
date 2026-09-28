import Observation
import TallyDomain

/// Drives the first-sync skeleton (UX-WP-10, ux-ui.md §3.2 stage 5). Consumes
/// `FirstSyncPublishing` — a protocol, not a concrete `RefreshCoordinator`
/// (which doesn't exist yet; connecting one is the app-core team's job) — and
/// turns its events into what the skeleton view needs: which phases are
/// done, whether it's finished or failed, and whether the "large course
/// loads" notice should show.
/// Explicitly `@MainActor`, with an explicit `nonisolated deinit` (plan 06 A2): see that deinit.
@MainActor
@Observable
public final class FirstSyncViewModel {
    /// Explicit and nonisolated (plan 06 A2). In this default-`MainActor` module the compiler makes an
    /// implicit deinit main-actor isolated, `@MainActor` on the class or not, and an isolated deinit
    /// (`swift_task_deinitOnExecutor`) aborts iOS 26.0-26.3 runtimes when it runs nested or in a
    /// task-local scope (swiftlang/swift#88036; the floor abort in CI run 36390172728). CI's `nm`
    /// gate keeps isolated deinits out of every shipping binary.
    nonisolated deinit {}

    public static let allPhases = FirstSyncPhase.allCases

    public let schoolDisplayName: String
    public private(set) var completedPhases: [FirstSyncPhase] = []
    public private(set) var isFinished = false
    public private(set) var failure: RefreshFailure?
    /// "If the sync takes more than 10 s with **no cache**, show 'Large
    /// course loads can take a minute — you can keep exploring', **not** the
    /// stale breadcrumb, because nothing is saved yet" (ux-ui.md §3.2 stage 5).
    /// Onboarding's first sync never has a cache, so this is the only variant
    /// this view model needs to model.
    public private(set) var showsSlowLoadNotice = false

    private let clock: any DateProviding
    private let slowLoadThreshold: Duration
    private var eventTask: Task<Void, Never>?
    private var slowLoadTask: Task<Void, Never>?

    public init(
        schoolDisplayName: String,
        publisher: any FirstSyncPublishing,
        clock: any DateProviding = SystemDateProvider(),
        slowLoadThreshold: Duration = .seconds(10)
    ) {
        self.schoolDisplayName = schoolDisplayName
        self.clock = clock
        self.slowLoadThreshold = slowLoadThreshold
        start(publisher)
    }

    /// "Setting up Tally · step N of 4" (ux-ui.md prototype `heroSkeleton`), or
    /// "Connecting to <School>…" before the first phase completes.
    public var statusText: String {
        guard let count = completedPhases.isEmpty ? nil : completedPhases.count else {
            return "Connecting to \(schoolDisplayName)…"
        }
        guard count < Self.allPhases.count else { return "Almost done" }
        return "Setting up Tally · step \(count + 1) of \(Self.allPhases.count)"
    }

    /// A determinate progress fraction in `0...1` (ux-ui.md's gold bar), never
    /// quite 0 (there's always a connection under way) or a flat 100% until
    /// `isFinished`.
    public var progress: Double {
        if isFinished { return 1 }
        let base = 0.08
        let perPhase = (0.9 - base) / Double(Self.allPhases.count)
        return base + Double(completedPhases.count) * perPhase
    }

    private func start(_ publisher: any FirstSyncPublishing) {
        eventTask = Task {
            for await event in publisher.events() {
                guard !Task.isCancelled else { return }
                apply(event)
            }
        }
        slowLoadTask = Task {
            try? await Task.sleep(for: slowLoadThreshold)
            guard !Task.isCancelled, !isFinished, failure == nil else { return }
            showsSlowLoadNotice = true
        }
    }

    private func apply(_ event: FirstSyncEvent) {
        switch event {
        case .phaseCompleted(let phase):
            guard !completedPhases.contains(phase) else { return }
            completedPhases.append(phase)
            AccessibilityAnnouncer.announce(phase.announcementText)
        case .finished:
            isFinished = true
            slowLoadTask?.cancel()
        case .failed(let reason):
            failure = reason
            slowLoadTask?.cancel()
        }
    }
}
