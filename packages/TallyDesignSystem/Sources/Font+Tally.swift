import SwiftUI

public extension Font {
    struct Tally {
        public static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        public static let title = Font.system(.title, design: .rounded, weight: .bold)
        public static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
        public static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        public static let body = Font.system(.body, design: .rounded, weight: .regular)
        public static let callout = Font.system(.callout, design: .rounded, weight: .regular)
        public static let caption = Font.system(.caption, design: .rounded, weight: .medium)
    }
}
