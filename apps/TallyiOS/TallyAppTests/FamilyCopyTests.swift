import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStrings
@testable import TallyFeatures

/// M3-E2 (FAM-10's "string-table test"): the confirmations read as family-linking.md §7.7 wrote
/// them, with the student's name in place of "Maya", and §7.6's states as §7.6 wrote them. Deviations
/// from the spec's words are deliberate and listed in the M3-E2 report: "add her back" names the
/// student instead of guessing a pronoun, and a parent's rejected code asks "your student" (the
/// parent may not know whose code it was). Also the switcher's helpers (§7.1).
@Suite("Family copy: §7.7 confirmations and §7.6 states, in English (M3-E2)")
@MainActor
struct FamilyCopyTests {
    private static func english(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = Locale(identifier: "en_US")
        return String(localized: resource)
    }

    @Test("§7.7: Unlink in Canvas")
    func unlinkCopy() {
        #expect(Self.english(L10n.FamilyUI.unlinkTitle("Maya")) == "Unlink Maya?")
        #expect(Self.english(L10n.FamilyUI.unlinkMessage("Maya")) ==
            "You'll stop seeing Maya's courses and grades in Tally, the Canvas Parent app and Canvas on the web. To link again, Maya will need to send you a new code. Tally will delete Maya's saved data from this iPhone.")
        #expect(Self.english(L10n.FamilyUI.unlinkConfirm()) == "Unlink")
        #expect(Self.english(L10n.Settings.cancel()) == "Cancel")
    }

    @Test("§7.7: Remove from Tally")
    func removeCopy() {
        #expect(Self.english(L10n.FamilyUI.removeTitle("Maya")) == "Remove Maya from Tally?")
        #expect(Self.english(L10n.FamilyUI.removeMessage("Maya")) ==
            "Maya stays linked to your Canvas account. Tally will delete Maya's saved data from this iPhone. You can add Maya back from Linked students.")
        #expect(Self.english(L10n.FamilyUI.removeFromTally()) == "Remove from Tally")
    }

    @Test("§7.7: a student's How to remove")
    func howToRemoveCopy() {
        #expect(Self.english(L10n.FamilyUI.howToRemoveHeading()) == "Only your school can remove an observer.")
        #expect(Self.english(L10n.FamilyUI.howToRemoveBody("Dana")) ==
            "Canvas doesn't let students unlink observers. Contact your school's Canvas support and ask them to remove Dana as an observer on your account.")
        #expect(Self.english(L10n.FamilyUI.removalRequest("Dana")) == "Please remove Dana as an observer on my Canvas account.")
    }

    @Test("§7.6: every state's words")
    func stateCopy() {
        #expect(Self.english(L10n.FamilyUI.parentNoStudents()) ==
            "No students linked yet. Ask your student for a code from Tally (Settings → Family & Sharing) or from Canvas (Account → Settings → Pair with Observer).")
        #expect(Self.english(L10n.FamilyUI.studentNoObservers()) == "No one is linked to your Canvas account.")
        #expect(Self.english(L10n.FamilyUI.codeRejected()) ==
            "That code didn't work. Codes are case-sensitive, work once, and expire after 7 days. Ask your student for a new one.")
        #expect(Self.english(L10n.FamilyUI.inviteRefused("Northfield")) ==
            "Northfield hasn't turned on parent accounts in Canvas, so Tally can't create an invite.")
        #expect(Self.english(L10n.FamilyUI.scopeMissing()) == "Your school's Tally setup doesn't include parent invites yet.")
        #expect(Self.english(L10n.FamilyUI.linkRemoved("Maya")) ==
            "You're no longer linked to Maya in Canvas. Tally removed Maya's saved data from this iPhone.")
    }

    @Test("Each failure maps to its §7.6 state")
    func problemMapping() {
        #expect(FamilyLinkProblem(.invalidOrExpiredCode) == .codeRejected)
        #expect(FamilyLinkProblem(.selfRegistrationOff) == .inviteRefused)
        #expect(FamilyLinkProblem(.scopeMissing) == .scopeMissing)
        #expect(FamilyLinkProblem(.throttled(nextAllowedAt: .distantFuture)) == .throttled)
        #expect(FamilyLinkProblem(.network(.unknown)) == .network)
        #expect(FamilyLinkProblem(failure: CancellationError()) == .network)
    }

    @Test("§7.1: first name, initials, the 15-character cut, the spelled code; §7.4's share text keeps the code out of any link")
    func switcherText() {
        #expect(StudentNameText.firstName(of: "Rowan Sample") == "Rowan")
        #expect(StudentNameText.initials(of: "Rowan Sample") == "RS")
        #expect(StudentNameText.initials(of: "maya") == "M")
        #expect(StudentNameText.initials(of: "  ") == "")
        #expect(StudentNameText.truncated("Maximilianowski") == "Maximilianowski") // 15: kept
        #expect(StudentNameText.truncated("Maximilianowskis") == "Maximilianowsk\u{2026}")
        #expect(StudentNameText.spelled("X7Q2KP") == "X, 7, Q, 2, K, P")

        let invite = PairingInvite(code: "X7Q2KP", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        for text in [PairingInviteText.shareMessage(invite, school: "Northfield"), PairingInviteText.shareMessage(invite, school: nil)] {
            #expect(text.contains("Enter code X7Q2KP"))
            #expect(!text.contains("://"), "the share text carries a link: \(text)")
        }
    }

    @Test("§7.1: six avatar colours, each with white initials at 4.5:1 or more, cycling past six")
    func avatarPalette() {
        #expect(FamilyAvatarPalette.colors.count == 6)
        #expect(Set(FamilyAvatarPalette.colors.map { "\($0.red),\($0.green),\($0.blue)" }).count == 6)
        for color in FamilyAvatarPalette.colors {
            #expect(FamilyAvatarPalette.contrastWithWhite(color) >= 4.5, "\(color)")
        }
        #expect(FamilyAvatarPalette.color(at: 7) == FamilyAvatarPalette.color(at: 1))
        #expect(FamilyAvatarPalette.color(at: -1) == FamilyAvatarPalette.color(at: 5))
    }
}
