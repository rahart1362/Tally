import Foundation
import TallyCanvasAPI
import TallyDomain

/// The family screens' named values (family-linking.md §7.1).
nonisolated enum FamilyUIConfig {
    /// The switcher's initials circle, in points.
    static let avatarDiameter: Double = 28
    /// The switcher's minimum tap height (HIG: 44 points).
    static let minimumHitTarget: Double = 44
    /// The HIG asks for titles "under 15 characters"; a longer first name ends in an ellipsis.
    static let switcherNameLimit = 15
    /// Pairing codes still pending on this iPhone before "Create Code" warns that Canvas turns the
    /// oldest unused one off (§7.4 step 6).
    static let pendingInvitesBeforeWarning = 5
    /// How long a pairing code works (Canvas: 7 days; family-linking.md §2.2). The sample service
    /// stamps its codes with it; a real code carries Canvas's own `expires_at`.
    static let pairingCodeLifetime: Duration = .seconds(7 * 24 * 60 * 60)
    /// A sample pairing code's length (Canvas's codes are 6 characters, §7.5 step 4).
    static let pairingCodeLength = 6
}

/// One linked student as the family screens show them (family-linking.md §7.1, §7.3): the opaque
/// subject, the name Canvas reported and the school. The name stays in memory only: storage keys
/// a student by `subject.id`, never by name (§6.3).
public nonisolated struct FamilyStudent: Sendable, Equatable, Identifiable {
    public let subject: Subject
    public let canvasUserID: String
    public let name: String
    public let school: String

    public var id: SubjectKey { subject.id }
    /// The name the switcher, the confirmations and the notifications use ("Maya").
    public var firstName: String { StudentNameText.firstName(of: name) }
    /// Up to two letters for the initials circle ("MS").
    public var initials: String { StudentNameText.initials(of: name) }

    public init(subject: Subject, canvasUserID: String, name: String, school: String) {
        self.subject = subject
        self.canvasUserID = canvasUserID
        self.name = name
        self.school = school
    }
}

/// How a student's name is shortened for the header (pure, so a hosted test pins it).
nonisolated enum StudentNameText {
    /// The first word of `name`, or the whole trimmed name when it has one word (or none).
    static func firstName(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        return words.first.map(String.init) ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first letters of the first and the last word, upper-cased in the user's locale; one letter
    /// for a one-word name; empty for an empty name.
    static func initials(of name: String, locale: Locale = .autoupdatingCurrent) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased(with: locale) }
        return (String(first) + String(last)).uppercased(with: locale)
    }

    /// `text` cut to `limit` characters with a tail ellipsis when it is longer.
    static func truncated(_ text: String, limit: Int = FamilyUIConfig.switcherNameLimit) -> String {
        guard text.count > limit, limit > 1 else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }

    /// A pairing code one character at a time, for VoiceOver ("X, 7, Q, 2, K, P", §7.4 step 3): the
    /// commas make VoiceOver pause between characters instead of reading a word.
    static func spelled(_ code: String) -> String {
        code.map(String.init).joined(separator: ", ")
    }
}

/// The switcher's six avatar colours (family-linking.md §7.1): sRGB, each dark enough that white
/// initials on it reach WCAG's 4.5:1. A student's colour is their place in the roster, so siblings
/// differ up to six. Colour is never the only cue: the name is always shown beside it.
nonisolated enum FamilyAvatarPalette {
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    static let colors: [RGB] = [
        RGB(red: 0.153, green: 0.380, blue: 0.659), // blue
        RGB(red: 0.502, green: 0.239, blue: 0.659), // purple
        RGB(red: 0.651, green: 0.200, blue: 0.161), // red
        RGB(red: 0.110, green: 0.443, blue: 0.259), // green
        RGB(red: 0.588, green: 0.318, blue: 0.039), // amber
        RGB(red: 0.255, green: 0.329, blue: 0.408), // slate
    ]

    static func color(at index: Int) -> RGB {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// WCAG 2.x contrast ratio of white text on `color`.
    static func contrastWithWhite(_ color: RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        return 1.05 / (luminance + 0.05)
    }
}

/// What a failed link request shows (family-linking.md §7.6), from FAM-06's `LinkManagementError`.
nonisolated enum FamilyLinkProblem: Equatable, Sendable {
    /// "Code rejected" (W2 422/400).
    case codeRejected
    /// "Invite refused" (W1 401: the school has no parent self-registration).
    case inviteRefused
    /// "Scope missing on Tally's key" (the registry's `familyCapable` is off).
    case scopeMissing
    /// Tally's own write throttle (§6.7).
    case throttled
    /// Transport, auth or server trouble.
    case network

    init(_ error: LinkManagementError) {
        switch error {
        case .invalidOrExpiredCode: self = .codeRejected
        case .selfRegistrationOff: self = .inviteRefused
        case .scopeMissing: self = .scopeMissing
        case .throttled: self = .throttled
        case .network: self = .network
        }
    }

    /// Any failure: FAM-06's errors map as `init(_:)` does; anything else is a network problem.
    init(failure: any Error) {
        if let error = failure as? LinkManagementError {
            self.init(error)
        } else {
            self = .network
        }
    }
}
