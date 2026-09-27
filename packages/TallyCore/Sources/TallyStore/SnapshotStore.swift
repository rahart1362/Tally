import Foundation
import TallyDomain

/// Errors `SnapshotStore` raises itself (as opposed to a `VaultError` surfaced through
/// `SealedFileAccess`). These are programming/ordering mistakes, not runtime dispositions.
public enum SnapshotStoreError: Error, Equatable, Sendable {
    /// A commit's `generation` did not exceed the generation already on disk. `RefreshCoordinator`
    /// (TallySync, out of this worktree's scope) owns the single-flight/epoch guard that should
    /// make this unreachable in practice; this is a defensive, testable backstop.
    case staleGeneration(attempted: UInt64, current: UInt64)
}

/// What `loadSnapshot()` returns. Deliberately distinct from `SealedRead`: this layer has already
/// decoded JSON and applied the schema rule, so a caller never sees a `VaultError` it can't act on.
public enum SnapshotLoadResult: Equatable, Sendable {
    case loaded(CanvasSnapshot)
    /// Nothing usable is committed: never written, an old schema, or a corrupt/undecodable blob.
    /// The caller's job is the same in every case: refetch (`StoreFile.snapshot.isRederivable`).
    case absent
    /// Device locked, or an unclassified I/O error. The caller must NOT refetch or delete.
    case unavailable(VaultDisposition)
}

public enum GlanceLoadResult: Equatable, Sendable {
    case loaded(GlanceProjection)
    case absent
    case unavailable(VaultDisposition)
}

/// The sealed, versioned Codable snapshot store (architecture.md §3.2, WP-C01) plus its glance
/// projection, wired to the vault (WP-ENC-02): every read/write goes through `SealedFileAccess`,
/// never the file system or the sealer directly.
///
/// **Commit protocol:** seal the snapshot -> atomic write (temp file + rename, `ProtectedFile`) ->
/// build and atomic-write the glance. If the app crashes between those two writes, the only
/// possible on-disk state is a glance whose `generation` is older than the snapshot's (or a
/// missing/corrupt glance); `loadSnapshot()` detects that on the next load and rebuilds the glance
/// from the snapshot already on disk, so the store heals itself without discarding the snapshot.
///
/// **Schema rule:** an older `CanvasSnapshot.schemaVersion` is discarded, never migrated — the
/// snapshot is entirely re-fetchable, so there is nothing to preserve. `userState` and `ledger`
/// (see `UserStateStore`/`SyncLedgerStore`) are user-authored or side-effect state and get real
/// versioned migrations instead.
public actor SnapshotStore {
    private let layout: StoreLayout
    private let access: SealedFileAccess
    private let isOwner: Bool

    public init(root: URL, accountKey: AccountKey, sealer: any SnapshotSealer, isOwner: Bool = true) {
        layout = StoreLayout(root: root, accountKey: accountKey)
        access = SealedFileAccess(sealer: sealer, isOwner: isOwner)
        self.isOwner = isOwner
    }

    /// Creates the account directory (idempotent) with the requested protection class and backup
    /// exclusion. Callers should invoke this once before the first `commit`.
    public func prepare() throws {
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
    }

    /// Seals and atomically replaces the snapshot, then rebuilds and atomically replaces the
    /// glance from it. `includeGrades` is the caller's resolved `UserState.showGradesInGlance`
    /// (never defaulted to true by this type).
    @discardableResult
    public func commit(_ snapshot: CanvasSnapshot, includeGrades: Bool) throws -> GlanceProjection {
        if let current = currentOnDiskGeneration(), current >= snapshot.generation {
            throw SnapshotStoreError.staleGeneration(attempted: snapshot.generation, current: current)
        }
        try prepare()
        try access.write(try JSONEncoder().encode(snapshot), .snapshot, to: layout.url(for: .snapshot), excludeFromBackup: true)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: includeGrades)
        try writeGlance(glance)
        return glance
    }

    /// Decodes the on-disk snapshot, discarding (not migrating) an old schema version, and
    /// self-heals the glance if it is missing, corrupt, or behind the snapshot's generation.
    @discardableResult
    public func loadSnapshot() -> SnapshotLoadResult {
        switch access.read(.snapshot, at: layout.url(for: .snapshot)) {
        case .absent:
            return .absent
        case .failed(_, let disposition):
            return .unavailable(disposition)
        case .plaintext(let data):
            guard let decoded = try? JSONDecoder().decode(CanvasSnapshot.self, from: data),
                  decoded.schemaVersion == CanvasSnapshot.currentSchemaVersion else {
                if isOwner { ProtectedFile.remove(layout.url(for: .snapshot)) }
                return .absent
            }
            selfHealGlanceIfNeeded(for: decoded)
            return .loaded(decoded)
        }
    }

    /// The widget's fast path: read only `glance.v1.sealed`, without decoding the full snapshot.
    public func loadGlance() -> GlanceLoadResult {
        switch access.read(.glance, at: layout.url(for: .glance)) {
        case .absent:
            return .absent
        case .failed(_, let disposition):
            return .unavailable(disposition)
        case .plaintext(let data):
            guard let decoded = try? JSONDecoder().decode(GlanceProjection.self, from: data) else {
                if isOwner { ProtectedFile.remove(layout.url(for: .glance)) }
                return .absent
            }
            return .loaded(decoded)
        }
    }

    /// Removes anything in the account directory that isn't a recognised store file (e.g. a
    /// `.tmp` file orphaned by a crash mid atomic-write). Call once per foreground launch.
    public func sweepOrphanedTempFiles() {
        ProtectedFile.sweep(directory: layout.accountDirectory, keeping: StoreLayout.allFileNames)
    }

    // MARK: - Self-heal

    private func selfHealGlanceIfNeeded(for snapshot: CanvasSnapshot) {
        guard isOwner else { return } // a non-owner (the widget) never repairs anything
        let (needsRebuild, priorIncludedGrades) = glanceNeedsRebuild(comparedTo: snapshot.generation)
        guard needsRebuild else { return }
        let rebuilt = GlanceProjectionBuilder.build(from: snapshot, includeGrades: priorIncludedGrades)
        try? writeGlance(rebuilt)
    }

    /// Best-effort carry-forward of the grade opt-in signal from whatever glance is already on
    /// disk (defaulting to `false`, the private choice, when there is no signal to carry forward).
    /// The authoritative source for a normal `commit` is always the caller's `includeGrades`
    /// argument; this only matters for the self-heal path, which has no `UserState` in hand.
    private func glanceNeedsRebuild(comparedTo generation: UInt64) -> (needsRebuild: Bool, priorIncludedGrades: Bool) {
        switch access.read(.glance, at: layout.url(for: .glance)) {
        case .absent, .failed:
            return (true, false)
        case .plaintext(let data):
            guard let glance = try? JSONDecoder().decode(GlanceProjection.self, from: data) else { return (true, false) }
            let includedGrades = glance.overallGradeBand != nil || glance.courses.contains { $0.currentGrade != nil }
            return (glance.generation < generation, includedGrades)
        }
    }

    private func writeGlance(_ glance: GlanceProjection) throws {
        try access.write(try JSONEncoder().encode(glance), .glance, to: layout.url(for: .glance), excludeFromBackup: true)
    }

    /// Peeks the on-disk snapshot's generation without touching the glance; used only to guard
    /// against a caller committing a generation that is not strictly increasing.
    private func currentOnDiskGeneration() -> UInt64? {
        guard case .plaintext(let data) = access.read(.snapshot, at: layout.url(for: .snapshot)),
              let decoded = try? JSONDecoder().decode(CanvasSnapshot.self, from: data),
              decoded.schemaVersion == CanvasSnapshot.currentSchemaVersion else { return nil }
        return decoded.generation
    }
}
