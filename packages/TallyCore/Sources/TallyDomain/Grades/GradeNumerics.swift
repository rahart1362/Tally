import Foundation

// Numeric semantics of canvas-lms lib/grade_calculator.rb, as ported in
// tools/canvas-synth/canvas_synth/gradecalc.py. They decide the last digit:
//
// * group grades and the points-weighted course grade use BigDecimal with
//   `round(2)` (ROUND_HALF_UP): here Foundation `Decimal` + `NSDecimalRound(.plain)`;
// * the percent-weighted course grade and weighted-grading-period totals use
//   Ruby `Float#round(2)`: here `RubyNumerics.floatRound`, a bit-for-bit port;
// * `x.to_d` of a Float is the exact value of its shortest round-trip decimal
//   (Python `Decimal(repr(x))`): here `ShortestDecimal`.
//
// The Python port evaluates BigDecimal steps at 50 significant digits; `Decimal`
// carries 38. Every step is a sum, a product by a short decimal, or a quotient
// of short decimals whose value is either exact or at least ~1e-13 away from a
// rounding boundary, so the 12 missing digits cannot change a rounded result.

/// The shortest decimal that round-trips to a finite `Double` (Python `repr`,
/// Ruby `Float#to_s`): value = ±significand × 10^exponent.
struct ShortestDecimal: Equatable, Sendable {
    let negative: Bool
    let significand: UInt64
    let exponent: Int

    /// Swift's `description` prints exactly the shortest round-trip digits
    /// (e.g. "136.1", "1e-05", "1.2345678901234568e+17").
    init(_ value: Double) {
        precondition(value.isFinite, "grade inputs are finite")
        var text = Substring(value.description)
        negative = text.first == "-"
        if negative { text = text.dropFirst() }
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exponent = Int(text[text.index(after: e)...]) ?? 0
            text = text[..<e]
        }
        var digits = String(text)
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...]
            exponent -= fraction.count
            digits = String(text[..<dot]) + fraction
        }
        significand = UInt64(digits) ?? 0
        self.exponent = exponent
    }

    var decimal: Decimal {
        significand == 0 ? Decimal(0)
            : Decimal(sign: negative ? .minus : .plus, exponent: exponent, significand: Decimal(significand))
    }

    /// The value × 10^(-scale) as an exact integer; requires `scale <= exponent` unless the value is 0.
    func scaled(to scale: Int) -> BigInt {
        guard significand != 0 else { return BigInt(0) }
        let magnitude = BigInt(significand) * BigInt.pow10(exponent - scale)
        return negative ? -magnitude : magnitude
    }
}

enum RubyNumerics {
    /// Ruby `Float#to_d` / `BigDecimal(float.to_s)`.
    static func decimal(_ value: Double) -> Decimal { ShortestDecimal(value).decimal }

    /// Python `float(Decimal)` / Ruby `BigDecimal#to_f`: correctly rounded via the decimal text.
    static func double(_ value: Decimal) -> Double { Double(value.description) ?? .nan }

    /// Ruby `BigDecimal#round(2)` (ROUND_HALF_UP: ties away from zero).
    static func roundHalfUp2(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    private static let dblDig = 15

    /// C `round()`: half away from zero (written as in gradecalc.py `_c_round`).
    private static func cRound(_ x: Double) -> Double {
        let ax = abs(x)
        var f = ax.rounded(.down)
        if ax - f >= 0.5 { f += 1.0 }
        return Double(signOf: x, magnitudeOf: f)
    }

    /// Ruby `Float#round(ndigits)` for ndigits 1...14 (numeric.c: flo_round ->
    /// rb_float_round -> round_half_up), ported from gradecalc.py `ruby_float_round`.
    /// It rounds the *decimal literal* half up, so 93.825 -> 93.83 where Swift's
    /// `(x * 100).rounded() / 100` gives 93.82.
    static func floatRound(_ number: Double, _ ndigits: Int = 2) -> Double {
        precondition((1...14).contains(ndigits), "ported for ndigits 1...14 only")
        if number == 0.0 || !number.isFinite { return number }
        // frexp: number = m * 2^binexp with 0.5 <= |m| < 1
        let binexp = Int(number.exponent) + 1
        let floatDig = dblDig + 2
        // float_round_overflow (Swift `/` truncates toward zero, like C)
        if ndigits >= floatDig - (binexp > 0 ? binexp / 4 : binexp / 3 - 1) { return number }
        // float_round_underflow
        if number > 0.0 && ndigits < -(binexp > 0 ? binexp / 3 + 1 : binexp / 4) { return 0.0 }
        var s = 1.0
        for _ in 0..<ndigits { s *= 10.0 }   // exact: 10^n is representable for n <= 22
        var f = cRound(number * s)
        if number > 0 {
            if (f + 0.5) / s <= number { f += 1 }
        } else {
            if (f - 0.5) / s >= number { f -= 1 }
        }
        return f / s
    }
}

/// Minimal arbitrary-precision signed integer: exactly what the drop-rule
/// bisection needs (add, subtract, multiply, compare). No division.
struct BigInt: Equatable, Comparable, Sendable, CustomStringConvertible {
    /// Little-endian base-2^32 magnitude without high zero limbs; empty means 0.
    private let limbs: [UInt32]
    private let negative: Bool

    private init(limbs: [UInt32], negative: Bool) {
        var trimmed = limbs
        while trimmed.last == 0 { trimmed.removeLast() }
        self.limbs = trimmed
        self.negative = trimmed.isEmpty ? false : negative
    }

    init(_ value: Int) { self.init(magnitude: UInt64(value.magnitude), negative: value < 0) }
    init(_ value: UInt64) { self.init(magnitude: value, negative: false) }
    private init(magnitude: UInt64, negative: Bool) {
        self.init(limbs: [UInt32(truncatingIfNeeded: magnitude), UInt32(truncatingIfNeeded: magnitude >> 32)],
                  negative: negative)
    }

    var signum: Int { limbs.isEmpty ? 0 : (negative ? -1 : 1) }

    static func pow10(_ n: Int) -> BigInt {
        precondition(n >= 0)
        var result = BigInt(1)
        let ten = BigInt(10)
        for _ in 0..<n { result = result * ten }
        return result
    }

    static prefix func - (x: BigInt) -> BigInt { BigInt(limbs: x.limbs, negative: !x.negative) }

    static func + (lhs: BigInt, rhs: BigInt) -> BigInt {
        if lhs.negative == rhs.negative { return BigInt(limbs: addMagnitudes(lhs.limbs, rhs.limbs), negative: lhs.negative) }
        switch compareMagnitudes(lhs.limbs, rhs.limbs) {
        case 0: return BigInt(0)
        case 1: return BigInt(limbs: subtractMagnitudes(lhs.limbs, rhs.limbs), negative: lhs.negative)
        default: return BigInt(limbs: subtractMagnitudes(rhs.limbs, lhs.limbs), negative: rhs.negative)
        }
    }

    static func - (lhs: BigInt, rhs: BigInt) -> BigInt { lhs + (-rhs) }

    static func * (lhs: BigInt, rhs: BigInt) -> BigInt {
        BigInt(limbs: multiplyMagnitudes(lhs.limbs, rhs.limbs), negative: lhs.negative != rhs.negative)
    }

    static func < (lhs: BigInt, rhs: BigInt) -> Bool {
        if lhs.negative != rhs.negative { return lhs.negative }
        let c = compareMagnitudes(lhs.limbs, rhs.limbs)
        return lhs.negative ? c > 0 : c < 0
    }

    var description: String {
        guard !limbs.isEmpty else { return "0" }
        var magnitude = limbs
        var chunks: [UInt32] = []   // base 10^9, least significant first
        while !magnitude.isEmpty {
            var remainder: UInt64 = 0
            for i in stride(from: magnitude.count - 1, through: 0, by: -1) {
                let current = (remainder << 32) | UInt64(magnitude[i])
                magnitude[i] = UInt32(current / 1_000_000_000)
                remainder = current % 1_000_000_000
            }
            while magnitude.last == 0 { magnitude.removeLast() }
            chunks.append(UInt32(remainder))
        }
        var text = negative ? "-" : ""
        text += String(chunks[chunks.count - 1])
        for chunk in chunks.dropLast().reversed() {
            let part = String(chunk)
            text += String(repeating: "0", count: 9 - part.count) + part
        }
        return text
    }

    private static func compareMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
        return 0
    }

    private static func addMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity(max(a.count, b.count) + 1)
        var carry: UInt64 = 0
        for i in 0..<max(a.count, b.count) {
            let sum = UInt64(i < a.count ? a[i] : 0) + UInt64(i < b.count ? b[i] : 0) + carry
            result.append(UInt32(truncatingIfNeeded: sum))
            carry = sum >> 32
        }
        if carry != 0 { result.append(UInt32(carry)) }
        return result
    }

    /// |a| - |b| for |a| >= |b|.
    private static func subtractMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity(a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            var difference = Int64(a[i]) - Int64(i < b.count ? b[i] : 0) - borrow
            if difference < 0 { difference += 1 << 32; borrow = 1 } else { borrow = 0 }
            result.append(UInt32(difference))
        }
        return result
    }

    private static func multiplyMagnitudes(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var result = [UInt32](repeating: 0, count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            let ai = UInt64(a[i])
            for j in 0..<b.count {
                // (2^32-1)^2 + 2(2^32-1) = 2^64-1: cannot overflow.
                let t = ai * UInt64(b[j]) + UInt64(result[i + j]) + carry
                result[i + j] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
            result[i + b.count] = UInt32(carry)
        }
        return result
    }
}
