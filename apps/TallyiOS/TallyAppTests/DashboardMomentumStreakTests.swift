import Testing
@testable import TallyFeatures

/// Idea 3 (`pmo-audit/.build-audit/ideas1/report.md` §"Surface \"Momentum\" streak on the
/// Dashboard"): the Dashboard shows the existing Insights streak (`StreakInsight`, computed by
/// `InsightsBuilder.streak` in the projection layer, `HomeProjector.project(now:)` ->
/// `ScreenProjections.build`) as one line, reusing its headline verbatim. This pins the one bit of
/// new logic this feature adds — whether the line shows at all — without SwiftUI, the same
/// pattern `GradeNotInCanvasHeroTests` uses for `HeroCaption`.
@Suite("Dashboard momentum streak: when the line shows (Idea 3)")
struct DashboardMomentumStreakTests {
    @Test("A current streak, student mode: the row, with the streak's own headline, verbatim")
    func showsForAStudentWithAStreak() {
        let streak = StreakInsight(days: 3, headline: "3-day streak")
        #expect(DashboardMomentumStreak(streak, isParentModeHome: false) == .row("3-day streak"))
    }

    @Test("A 1-day streak still shows (the plural key's singular form)")
    func showsForAOneDayStreak() {
        let streak = StreakInsight(days: 1, headline: "1-day streak")
        #expect(DashboardMomentumStreak(streak, isParentModeHome: false) == .row("1-day streak"))
    }

    @Test("No current streak: hidden, student mode (never 'No current streak' on the Dashboard)")
    func hiddenWithNoStreak() {
        let streak = StreakInsight(days: 0, headline: "No current streak")
        #expect(DashboardMomentumStreak(streak, isParentModeHome: false) == .hidden)
    }

    @Test("Parent mode: hidden even with a current streak (not a parent-appropriate metric)")
    func hiddenInParentModeDespiteAStreak() {
        let streak = StreakInsight(days: 5, headline: "5-day streak")
        #expect(DashboardMomentumStreak(streak, isParentModeHome: true) == .hidden)
    }

    @Test("Parent mode with no streak either: still hidden")
    func hiddenInParentModeWithNoStreak() {
        let streak = StreakInsight(days: 0, headline: "No current streak")
        #expect(DashboardMomentumStreak(streak, isParentModeHome: true) == .hidden)
    }
}
