import Testing
@testable import TallyFeatures

/// UX-SPARK follow-up (owner review, 2026-10-03): the sparkline is scaled to its own range, padded
/// like the Insights trend, never Swift Charts' zero-based default that drew every course flat.
@Suite("Course sparkline: the vertical scale follows the course's own range")
struct CourseSparklineScaleTests {
    @Test("The domain is the series' minimum and maximum, padded by the Insights trend's axis padding")
    func paddedOwnRange() {
        let domain = CourseSparklineView.yDomain([87.2, 89.0, 91.5])
        #expect(domain.lowerBound == 87.2 - GradeTrend.axisPadding)
        #expect(domain.upperBound == 91.5 + GradeTrend.axisPadding)
    }

    @Test("A steady course keeps a narrow, honest range rather than a zero-based one")
    func steadyStaysNarrow() {
        let domain = CourseSparklineView.yDomain([93.4, 93.4])
        #expect(domain.lowerBound > 0)
        #expect(abs((domain.upperBound - domain.lowerBound) - 2 * GradeTrend.axisPadding) < 1e-9)
    }
}
