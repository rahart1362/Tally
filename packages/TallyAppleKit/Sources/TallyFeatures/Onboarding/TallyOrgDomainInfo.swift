import Foundation

/// Reads the single source of truth for Tally's owned domain: the
/// `TallyOrgDomain` Info.plist key, generated from `Config/Identity.xcconfig`'s
/// `TALLY_ORG_DOMAIN` (GO-LIVE GL-02 — "the app builds https://$(TALLY_ORG_DOMAIN)/...
/// at runtime from the TallyOrgDomain Info.plist key").
///
/// `TallyPlatform`'s `WebAuthPresenter` reads the same Info.plist key directly
/// (architecture.md §3.1: `TallyFeatures` and `TallyPlatform` do not depend on
/// each other), so this three-line reader is intentionally duplicated there
/// rather than shared through a new cross-module type.
enum TallyOrgDomainInfo {
    static var current: String {
        (Bundle.main.object(forInfoDictionaryKey: "TallyOrgDomain") as? String) ?? "tally-app.dev"
    }
}
