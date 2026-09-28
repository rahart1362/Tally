import SwiftUI

/// Text-style roles (ux-ui.md §3.5 "Typography"). Every role is a Dynamic
/// Type text style, never a fixed `.system(size:)` point size, so text
/// scales (fixing UX-05).
public enum TallyTypography {
    /// Screen title: `.largeTitle` bold, serif (New York) on brand screens.
    public static var screenTitle: Font {
        .system(.largeTitle, design: .serif).bold()
    }

    /// Section header: `.title3` semibold.
    public static var sectionHeader: Font {
        .system(.title3, design: .default).weight(.semibold)
    }

    /// Card/row title: `.headline`.
    public static var cardTitle: Font {
        .system(.headline)
    }

    /// Body copy: `.body`.
    public static var body: Font {
        .system(.body)
    }

    /// Row subtitle: `.subheadline`.
    public static var subheadline: Font {
        .system(.subheadline)
    }

    /// Meta / freshness text: `.footnote`.
    public static var footnote: Font {
        .system(.footnote)
    }

    /// Chips and axis labels: `.caption`. Never smaller (§3.5: "never below 11 pt").
    public static var caption: Font {
        .system(.caption)
    }
}
