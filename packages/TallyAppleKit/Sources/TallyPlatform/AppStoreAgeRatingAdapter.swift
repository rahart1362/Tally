import StoreKit
import TallyFeatures

/// EB-03 (matrix.md §2: "a change in the age rating of an app to be a significant change").
/// `AppStore.ageRatingCode` (iOS 26.2+, StoreKit): "the current age rating code for your app ...
/// compare it with the last known age rating to check if it has changed." The comparison itself is
/// `AgeRatingChangeDetector` (TallyDomain, pure); this adapter only reads the device's current
/// value.
public struct AppStoreAgeRatingAdapter: AppStoreAgeRatingReading {
    public init() {}

    public func currentAgeRatingCode() async -> Int? {
        guard #available(iOS 26.2, *) else { return nil }
        return await AppStore.ageRatingCode
    }
}
