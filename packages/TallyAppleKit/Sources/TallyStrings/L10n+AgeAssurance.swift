import Foundation

/// AGE-1 (engineering-backlog-us.md §2 EB-01(e)/EB-02(b)): the neutral restricted screen
/// (`AgeRestrictedView`, TallyFeatures). A file of its own, as `L10n+Subscription.swift` is, so
/// other streams' files stay untouched. New keys, both approved 2026-10-21 (title as drafted;
/// body without "safe"); Spanish is a machine pass (`needs_review`).
extension L10n {
    public enum AgeAssurance {
        public static func restrictedTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "ageAssurance.restricted.title", defaultValue: "Parent or Guardian Permission Needed", bundle: #bundle,
                comment: "The restricted screen's title, shown instead of the Dashboard while a parent or guardian's consent for a minor is pending or was withdrawn (AGE-1 EB-01(e)/EB-02(b)).")
        }

        public static func restrictedBody() -> LocalizedStringResource {
            LocalizedStringResource(
                "ageAssurance.restricted.body", defaultValue: "A parent or guardian needs to approve this before you can keep using Tally. Your saved data stays on this iPhone in the meantime.", bundle: #bundle,
                comment: "The restricted screen's explanation. No button offers a way past it: the screen stays until Apple reports that consent was given (AGE-1 EB-01(e)).")
        }
    }
}
