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

    /// An inset-grouped `List` section header's own style on iOS 26, for a heading drawn as a row
    /// (Calendar's day headings, which must be rows to be `scrollTo` targets). Measured on the
    /// system header "Mon, Oct 12" (scope=a11y run 38550012702, light-std): cap height 12.0 pt and
    /// a 2 pt stem, so 17 pt semibold, which is `.headline`.
    public static var listHeader: Font {
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

    /// An empty or error state's title at the accessibility sizes (`TallyUnavailableView`):
    /// `.title2` bold, the system `ContentUnavailableView`'s own title style.
    public static var stateTitle: Font {
        .system(.title2).bold()
    }

    /// An empty or error state's symbol at the accessibility sizes (`TallyUnavailableView`):
    /// `.largeTitle`, a little smaller than the system view's, which leaves more of an AX5 screen
    /// for the words.
    public static var stateSymbol: Font {
        .system(.largeTitle)
    }
}
