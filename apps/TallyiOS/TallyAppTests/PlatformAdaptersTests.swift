import Foundation
import Testing
import TallyCanvasAPI
@testable import TallyPlatform

/// E03b: OSLogLogger (typed events, extended in this batch), ProtectionState,
/// and WidgetReloader.
@Suite("Platform logging, protection state and widget reload")
struct PlatformAdaptersTests {
    @Test("every new PlatformLogEvent case can be logged without crashing")
    func logsEveryNewCase() {
        let logger = OSLogPlatformLogger()
        logger.log(.transportFailed(.offline))
        logger.log(.transportFailed(.timedOut))
        logger.log(.transportFailed(.cancelled))
        logger.log(.transportFailed(.other))
        logger.log(.credentialStoreRead(found: true))
        logger.log(.credentialStoreRead(found: false))
        logger.log(.credentialStoreUnavailable)
        logger.log(.credentialStoreWriteFailed(status: -25308))
        logger.log(.legacyCredentialRemoved)
        logger.log(.vaultKeyStoreUnavailable)
        logger.log(.vaultKeyStoreWriteFailed(status: -50))
        logger.log(.notificationScheduleFailed)
        logger.log(.notificationCategoriesRegistered(count: 1))
        logger.log(.protectedDataDidBecomeAvailable)
        logger.log(.protectedDataDidBecomeUnavailable)
    }

    @Test("TransportError -> category string mapping is total and stable (mutation-guarded)")
    func transportErrorCategoryMapping() {
        #expect(OSLogPlatformLogger.category(of: .offline) == "offline")
        #expect(OSLogPlatformLogger.category(of: .timedOut) == "timedOut")
        #expect(OSLogPlatformLogger.category(of: .cancelled) == "cancelled")
        #expect(OSLogPlatformLogger.category(of: .other) == "other")
    }

    @Test("ProtectionState reports true once a hosted test process is running")
    func protectionStateIsAvailable() async {
        let state = ProtectionState()
        #expect(await state.isProtectedDataAvailable == true)
    }

    @Test("WidgetReloader's calls complete without throwing, with no widgets installed")
    func widgetReloaderDoesNotCrash() {
        let reloader = WidgetReloader()
        reloader.reloadAllTimelines()
        reloader.reloadTimelines(ofKind: "TallyGlanceWidget")
        #expect(Bool(true))
    }
}
