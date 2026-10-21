import Testing
@testable import TallyFeatures

/// FEAT-2 (school-check hardening of the subscription path): the sample-mode interstitial's two
/// states (`SubscriptionSettingsView.swift`), as a pure value independent of the view — so both
/// states, including the fallback App-Review path, are provable without a UI test. No DEBUG-only
/// test support here, so this stays in the `ios-perf` Release test build too.
@Suite("FEAT-2: the sample-mode interstitial's two states")
struct SampleInterstitialStateTests {
    @Test("no stored name (never searched, or cleared): .generic — today's copy, unchanged")
    func noStoredNameIsGeneric() {
        #expect(SampleInterstitialState(notEnabledSchoolName: nil) == .generic)
        #expect(!SampleInterstitialState(notEnabledSchoolName: nil).isNamed)
    }

    @Test("a stored name: .named, trimmed")
    func storedNameIsNamed() {
        #expect(SampleInterstitialState(notEnabledSchoolName: "Example High") == .named("Example High"))
        #expect(SampleInterstitialState(notEnabledSchoolName: "Example High").isNamed)
        // Whitespace the store never writes on its own, handled defensively rather than shown verbatim.
        #expect(SampleInterstitialState(notEnabledSchoolName: "  Example High  ") == .named("Example High"))
    }

    @Test("blank or whitespace-only: falls back to .generic rather than naming an empty school")
    func blankFallsBackToGeneric() {
        #expect(SampleInterstitialState(notEnabledSchoolName: "") == .generic)
        #expect(SampleInterstitialState(notEnabledSchoolName: "   ") == .generic)
    }
}
