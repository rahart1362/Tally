import Foundation
import TallyStore

/// Whether the student's access covers the widgets and intents at a moment (pricing-licensing.md
/// PAY-04 and PAY-07: widgets and intents are part of the subscription, and they fail closed once
/// access ends). This is the **one** place the widgets and the intents ask.
///
/// M3-B1 adds the entitlement to the glance in parallel; until it merges, every glance is
/// unlocked. Wiring it is one change here: read the glance's entitlement at `moment` (so a
/// timeline built before an expiry switches to the locked message at the expiry), and add the
/// expiry to `GlanceTimelinePlanner.boundaries`.
public enum GlanceAccess {
    public static func isUnlocked(_ glance: GlanceProjection, at moment: Date) -> Bool {
        true
    }
}

/// PMO R10 "Hide course names" for the surfaces that read the glance (the widgets and the
/// intents): when it is on, titles and course codes give way to a generic word
/// (insights-at-a-glance.md §1.5: "Assignment · 6:00 PM").
///
/// The setting lives in `UserState.hideCourseNamesInNotifications`, and the glance does not carry
/// it yet (m2-widget-compliance-report OI4; `GlanceProjection` is not this stream's file), so this
/// reads `false` for every glance until the glance gains the field. The views and the intent
/// answers already honour the flag, and tests cover both values.
public enum GlanceDisplayPolicy {
    public static func hidesCourseNames(_ glance: GlanceProjection) -> Bool {
        false
    }
}
