import Foundation

/// MVP-2b: line-break opportunities inside a value that is one long word — a web address
/// ("canvas.northfield.example") or a price ("$9.99/year").
///
/// With no space in it, such a value can only wrap mid-word: the sign-in hand-off read
/// "canvas.northfield.ex- / ample" at the default size and "can- / vas.north- / field.exam- / ple"
/// at AX5 (scope=a11y run 38338079168, iPhone 17 Pro), which breaks ux-fp2's rule that a value never
/// breaks mid-token, and Xcode's audit reported it as text that "may be clipped at larger Dynamic
/// Type sizes". `breakable(_:)` adds a zero-width space after each `.` or `/` that is followed by
/// a letter, so the line breaks at the value's own separators ("canvas." / "northfield." /
/// "example", "$9.99/" / "year") and nowhere else; a decimal point ("9.99") is left alone.
/// Display only: the zero-width space is invisible and VoiceOver skips it, but pass the original
/// string wherever the value is compared, stored or spoken as a label.
public enum TallyTokenBreaks {
    /// U+200B ZERO WIDTH SPACE: a line-break opportunity with no width.
    public static let opportunity: Character = "\u{200B}"

    public static func breakable(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count + 4)
        var previous: Character?
        for character in value {
            if let previous, previous == "." || previous == "/", character.isLetter {
                result.append(opportunity)
            }
            result.append(character)
            previous = character
        }
        return result
    }
}
