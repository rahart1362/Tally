import Synchronization
import TallyCanvasAPI

/// Records every store operation in order, so tests can prove "saved before resumed".
public final class InMemoryCredentialStore: CredentialStore {
    private let state: Mutex<(credential: CanvasCredential?, log: [String])>
    public init(_ credential: CanvasCredential? = nil) { state = Mutex((credential, [])) }

    public var credential: CanvasCredential? { state.withLock { $0.credential } }
    public var log: [String] { state.withLock { $0.log } }
    public func note(_ entry: String) { state.withLock { $0.log.append(entry) } }

    public func load() async -> CanvasCredential? { credential }
    public func save(_ credential: CanvasCredential) async throws {
        state.withLock { $0.credential = credential; $0.log.append("saved:\(credential.accessToken)") }
    }
    public func delete() async { state.withLock { $0.credential = nil; $0.log.append("deleted") } }
}
