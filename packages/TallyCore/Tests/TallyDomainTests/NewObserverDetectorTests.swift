import Foundation
import Testing
@testable import TallyDomain

@Suite("NewObserverDetector: seeding, one alert per new observer, no alert on removal (FAM-07)")
struct NewObserverDetectorTests {
    @Test func firstRefreshEverSeedsSilently() {
        let alerts = NewObserverDetector.detect(currentObserverIDs: ["9001", "9002"], previouslySeenObserverIDs: nil)
        #expect(alerts.isEmpty)
    }

    @Test func oneNewObserverYieldsExactlyOneAlert() {
        let alerts = NewObserverDetector.detect(currentObserverIDs: ["9001", "9002"], previouslySeenObserverIDs: ["9001"])
        #expect(alerts == [NewObserverAlert(observerCanvasUserID: "9002")])
    }

    @Test func multipleNewObserversYieldOneAlertEachInResultOrder() {
        let alerts = NewObserverDetector.detect(currentObserverIDs: ["9001", "9002", "9003"], previouslySeenObserverIDs: [])
        #expect(alerts == [
            NewObserverAlert(observerCanvasUserID: "9001"),
            NewObserverAlert(observerCanvasUserID: "9002"),
            NewObserverAlert(observerCanvasUserID: "9003"),
        ])
    }

    @Test func noChangeYieldsNoAlerts() {
        let alerts = NewObserverDetector.detect(currentObserverIDs: ["9001", "9002"], previouslySeenObserverIDs: ["9001", "9002"])
        #expect(alerts.isEmpty)
    }

    @Test func aRemovedObserverYieldsNoAlert() {
        let alerts = NewObserverDetector.detect(currentObserverIDs: ["9001"], previouslySeenObserverIDs: ["9001", "9002"])
        #expect(alerts.isEmpty)
    }

    @Test func simultaneousAdditionAndRemovalOnlyAlertsTheAddition() {
        let alerts = NewObserverDetector.detect(currentObserverIDs: ["9001", "9003"], previouslySeenObserverIDs: ["9001", "9002"])
        #expect(alerts == [NewObserverAlert(observerCanvasUserID: "9003")])
    }

    @Test func emptyToEmptyOnASubsequentRefreshYieldsNoAlerts() {
        // Distinguishes "zero observers, but this isn't the first refresh" (previouslySeen
        // is an empty Set, not nil) from the true first-refresh seeding case.
        let alerts = NewObserverDetector.detect(currentObserverIDs: [], previouslySeenObserverIDs: [])
        #expect(alerts.isEmpty)
    }
}
