import SwiftUI

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    struct Tally {
        public static let navyBackground = Color(hex: "#0D1B2A")
        public static let brandGold = Color(hex: "#E5B75A")
        
        public static let calculusBlue = Color(hex: "#3B82F6")
        public static let psychologyGreen = Color(hex: "#10B981")
        public static let biologyPurple = Color(hex: "#8B5CF6")
        public static let historyOrange = Color(hex: "#F59E0B")
        public static let englishBlue = Color(hex: "#0EA5E9")
        
        public static let alertRed = Color(hex: "#EF4444")
        
        public static let textPrimary = Color(hex: "#111827")
        public static let textSecondary = Color(hex: "#6B7280")
        
        public static let cardBackground = Color(hex: "#FFFFFF")
        public static let lightGrayBg = Color(hex: "#F9FAFB")
        public static let divider = Color(hex: "#E5E7EB")
    }
}
