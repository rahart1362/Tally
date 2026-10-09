import Foundation
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

/// UX-SPARK-2: the point/ring/grid opacities are named constants, not magic numbers scattered
/// across `CourseSparklineView`'s drawing code (the Tests section's lean requirement).
@Suite("UX-SPARK-2: the sparkline's style constants")
struct CourseSparklineStyleTests {
    @Test("The line, point and ring are each a named size, never below the line's own weight")
    func namedSizes() {
        #expect(CourseSparklineStyle.lineWidth == 2)
        #expect(CourseSparklineStyle.pointDiameter == 3)
        #expect(CourseSparklineStyle.endRingDiameter == 8)
        #expect(CourseSparklineStyle.endRingStrokeWidth == 2)
        #expect(CourseSparklineStyle.maximumTypeScale == 2)
    }

    @Test("Gridlines are fainter on the navy heroes than on a light card (cream vs. silver)")
    func gridlineOpacitiesByBackground() {
        #expect(CourseSparklineStyle.horizontalGridlineOpacityOnHero < CourseSparklineStyle.horizontalGridlineOpacityOnCard)
        #expect(CourseSparklineStyle.verticalGridlineOpacityOnHero < CourseSparklineStyle.verticalGridlineOpacityOnCard)
        // The owner's mock-up: 3 horizontal gridlines.
        #expect(CourseSparklineStyle.horizontalGridlineCount == 3)
    }

    @Test("Three horizontal gridlines sit at the domain's interior quartiles, never at its edges")
    func horizontalGridValuesAreInteriorQuartiles() {
        let values = CourseSparklineStyle.horizontalGridValues(80...100)
        #expect(values == [85, 90, 95])
    }

    @Test("Vertical week columns land weekly, strictly between the first and last point")
    func weekColumnDatesStepWeekly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = Date(timeIntervalSince1970: 0)
        let columns = CourseSparklineStyle.weekColumnDates(from: start, to: start.addingTimeInterval(20 * 86_400),
                                                            calendar: calendar)
        #expect(columns == [start.addingTimeInterval(7 * 86_400), start.addingTimeInterval(14 * 86_400)])
        // Fewer than a week of data: no columns at all, never one past the last point.
        #expect(CourseSparklineStyle.weekColumnDates(from: start, to: start.addingTimeInterval(3 * 86_400),
                                                     calendar: calendar).isEmpty)
    }
}
