import Foundation
@testable import TallyStore

/// A fresh, protected scratch directory for one test. Shared by every `TallyStoreTests` file
/// that needs a real (Linux temp-filesystem) location to read and write through `ProtectedFile`.
func tempStoreDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-store-\(UUID().uuidString)")
    try ProtectedFile.prepareDirectory(url, excludeFromBackup: true)
    return url
}
