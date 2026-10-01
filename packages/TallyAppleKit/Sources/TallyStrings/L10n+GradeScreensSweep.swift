import Foundation

/// Plan 08 L10N-03b: the grade-screens literal sweep (`Dashboard`, `Courses`, `CourseDetail`,
/// `Insights`, `ToDo`, `Home`'s tab bar, the sample-data banner, and `TallyPlatform`'s generic
/// notification content). Kept in its own file, beside `L10n.swift`, for the same reason
/// `L10n+GradeControls.swift` is: this stream's additions never touch the lines another stream
/// adds there, and every key is in the same catalog (plan 08 §5 row L10N-03b).
extension L10n.Dashboard {
    public static func failedTitle() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.failed.title", defaultValue: "No dashboard yet", bundle: #bundle,
                                comment: "Dashboard: shown when the student is signed out and not in sample mode.")
    }

    public static func failedDescription() -> LocalizedStringResource {
        LocalizedStringResource(
            "dashboard.failed.description", defaultValue: "Sign in, or explore with sample data, to see your dashboard.",
            bundle: #bundle, comment: "Dashboard failed-state body text.")
    }

    /// Shown both while loading (a skeleton) and once loaded: byte-identical in both places.
    public static func nextUpHeader() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.nextUpHeader", defaultValue: "Next up", bundle: #bundle,
                                comment: "Dashboard section header, shown both while loading (a skeleton) and once loaded.")
    }

    public static func needsAttentionHeader() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.needsAttentionHeader", defaultValue: "Needs attention", bundle: #bundle,
                                comment: "Dashboard section header, shown both while loading (a skeleton) and once loaded.")
    }

    public static func navigationTitle() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.navigationTitle", defaultValue: "Dashboard", bundle: #bundle,
                                comment: "The Dashboard tab's navigation title.")
    }

    /// "Good morning, Alex": `time` is one of `greetingMorning`/`greetingAfternoon`/`greetingEvening`,
    /// already resolved to a `String`; `name` is the student's Canvas display name, never translated.
    public static func greeting(_ time: String, _ name: String) -> LocalizedStringResource {
        LocalizedStringResource("dashboard.greeting", defaultValue: "Good \(time), \(name)", bundle: #bundle,
                                comment: "Dashboard's header above the hero. 1: a time-of-day word, already localized. 2: the student's display name from Canvas, never translated.")
    }

    public static func greetingMorning() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.greeting.morning", defaultValue: "morning", bundle: #bundle,
                                comment: "The time-of-day word in the Dashboard's greeting ('Good morning, Alex').")
    }

    public static func greetingAfternoon() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.greeting.afternoon", defaultValue: "afternoon", bundle: #bundle,
                                comment: "The time-of-day word in the Dashboard's greeting ('Good afternoon, Alex').")
    }

    public static func greetingEvening() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.greeting.evening", defaultValue: "evening", bundle: #bundle,
                                comment: "The time-of-day word in the Dashboard's greeting ('Good evening, Alex').")
    }

    public static func loading() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.loading", defaultValue: "Loading your dashboard\u{2026}", bundle: #bundle,
                                comment: "Dashboard: shown while the first projection is loading.")
    }

    public static func skeletonRow() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.skeletonRow", defaultValue: "Loading this section", bundle: #bundle,
                                comment: "Dashboard's loading skeleton: a redacted placeholder row shown under a section header before the full projection arrives.")
    }

    /// The placeholder is the section's own header text, already localized and resolved to `String`.
    public static func skeletonSectionSpoken(_ title: String) -> LocalizedStringResource {
        LocalizedStringResource("dashboard.skeletonSection.spoken", defaultValue: "\(title), loading", bundle: #bundle,
                                comment: "Accessibility label of a Dashboard skeleton section while it loads.")
    }

    public static func nextUpEmpty() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.nextUp.empty", defaultValue: "Nothing to do right now", bundle: #bundle,
                                comment: "Dashboard's Next Up section when there is nothing to do.")
    }

    public static func needsAttentionEmpty() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.needsAttention.empty", defaultValue: "All clear", bundle: #bundle,
                                comment: "Dashboard's Needs Attention section when nothing needs attention.")
    }

    public static func weekAheadHeader() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.weekAheadHeader", defaultValue: "Week ahead", bundle: #bundle,
                                comment: "Dashboard section header above the week strip.")
    }

    public static func dueSoonHeader() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.dueSoonHeader", defaultValue: "Due soon", bundle: #bundle,
                                comment: "Dashboard section header above the due-soon list.")
    }

    public static func dueSoonEmpty() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.dueSoon.empty", defaultValue: "Nothing due in the next 7 days", bundle: #bundle,
                                comment: "Dashboard's Due Soon section when nothing is due in the next 7 days.")
    }

    public static func bandPassing() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.band.passing", defaultValue: "Passing", bundle: #bundle,
                                comment: "Dashboard hero's grade band word for a pass/fail course that is passing.")
    }

    public static func bandFailing() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.band.failing", defaultValue: "Failing", bundle: #bundle,
                                comment: "Dashboard hero's grade band word for a pass/fail course that is failing.")
    }

    public static func bandHigh() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.band.high", defaultValue: "High", bundle: #bundle,
                                comment: "Dashboard Next Up item's priority band word.")
    }

    public static func bandMedium() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.band.medium", defaultValue: "Medium", bundle: #bundle,
                                comment: "Dashboard Next Up item's priority band word.")
    }

    public static func bandLow() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.band.low", defaultValue: "Low", bundle: #bundle,
                                comment: "Dashboard Next Up item's priority band word.")
    }
}

// MARK: - Home shell (tab bar) and Sample Data banner

extension L10n {
    /// The Home shell's tab bar (`TallyFeatures/Home/HomeShellView.swift`).
    public enum Home {
        public static func tabDashboard() -> LocalizedStringResource {
            LocalizedStringResource("home.tab.dashboard", defaultValue: "Dashboard", bundle: #bundle,
                                    comment: "Home shell tab bar label.")
        }

        public static func tabCourses() -> LocalizedStringResource {
            LocalizedStringResource("home.tab.courses", defaultValue: "Courses", bundle: #bundle,
                                    comment: "Home shell tab bar label.")
        }

        public static func tabCalendar() -> LocalizedStringResource {
            LocalizedStringResource("home.tab.calendar", defaultValue: "Calendar", bundle: #bundle,
                                    comment: "Home shell tab bar label.")
        }

        public static func tabToDo() -> LocalizedStringResource {
            LocalizedStringResource("home.tab.toDo", defaultValue: "To-Do", bundle: #bundle,
                                    comment: "Home shell tab bar label.")
        }

        public static func tabInsights() -> LocalizedStringResource {
            LocalizedStringResource("home.tab.insights", defaultValue: "Insights", bundle: #bundle,
                                    comment: "Home shell tab bar label.")
        }

        public static func settingsButton() -> LocalizedStringResource {
            LocalizedStringResource("home.settingsButton", defaultValue: "Settings", bundle: #bundle,
                                    comment: "Accessibility label of the Home shell's Settings toolbar button (a person icon).")
        }
    }

    /// The persistent sample-data banner (`TallyFeatures/SampleData/SampleDataBanner.swift`; ASC-14).
    public enum SampleData {
        public static func bannerLabel() -> LocalizedStringResource {
            LocalizedStringResource("sampleData.banner.label", defaultValue: "SAMPLE DATA", bundle: #bundle,
                                    comment: "The persistent banner shown above every screen in sample-data mode.")
        }

        public static func bannerExit() -> LocalizedStringResource {
            LocalizedStringResource("sampleData.banner.exit", defaultValue: "Exit", bundle: #bundle,
                                    comment: "Sample-data banner's button that leaves sample mode, back to Welcome.")
        }
    }
}

// MARK: - Courses (tab, cards, health, formatter)

extension L10n.Courses {
    public static func navigationTitle() -> LocalizedStringResource {
        LocalizedStringResource("courses.navigationTitle", defaultValue: "Courses", bundle: #bundle,
                                comment: "The Courses tab's navigation title.")
    }

    /// The reorder toolbar button, not yet editing ("Edit", distinct context from a sheet's Done).
    public static func editButton() -> LocalizedStringResource {
        LocalizedStringResource("courses.edit.editButton", defaultValue: "Edit", bundle: #bundle,
                                comment: "Courses tab toolbar button that enters reorder mode.")
    }

    public static func editDoneButton() -> LocalizedStringResource {
        LocalizedStringResource("courses.edit.doneButton", defaultValue: "Done", bundle: #bundle,
                                comment: "Courses tab toolbar button that leaves reorder mode.")
    }

    public static func loading() -> LocalizedStringResource {
        LocalizedStringResource("courses.loading", defaultValue: "Loading your courses\u{2026}", bundle: #bundle,
                                comment: "Courses tab: shown while the first projection is loading.")
    }

    public static func emptyTitle() -> LocalizedStringResource {
        LocalizedStringResource("courses.empty.title", defaultValue: "No courses yet", bundle: #bundle,
                                comment: "Courses tab: shown when the student has no courses.")
    }

    public static func emptyDescription() -> LocalizedStringResource {
        LocalizedStringResource(
            "courses.empty.description", defaultValue: "When your school adds you to courses in Canvas, they'll appear here.",
            bundle: #bundle, comment: "Courses tab, empty state body text.")
    }

    public static func emptyRefresh() -> LocalizedStringResource {
        LocalizedStringResource("courses.empty.refresh", defaultValue: "Refresh", bundle: #bundle,
                                comment: "Courses tab, empty state: button that requests a refresh.")
    }

    /// A plural key: how many missing items are still accepted. English's "one" category only
    /// matches exactly 1, so the placeholder reads "1" there too.
    public static func missingItemsStillAccepted(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "courses.health.missingItemsStillAccepted", defaultValue: "\(count) missing item\(count == 1 ? "" : "s") is still accepted",
            bundle: #bundle, comment: "A course card/detail reason: how many missing items are still accepted.")
    }

    /// The placeholder is an already-formatted percentage: the student's goal.
    public static func belowGoalReason(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.health.belowGoalReason", defaultValue: "Below your \(percent) goal", bundle: #bundle,
                                comment: "A course's 'needs attention'/'at risk' reason.")
    }

    /// 1: a gap phrase ("Just above"/"1 point above"/"0.4 points above"). 2: an already-formatted
    /// percentage, the goal.
    public static func aboveGoalReason(_ gap: String, _ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.health.aboveGoalReason", defaultValue: "\(gap) your \(percent) goal", bundle: #bundle,
                                comment: "A course's 'needs attention' reason: the score is just above the goal.")
    }

    public static func aboveCutoffReason(_ gap: String, _ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.health.aboveCutoffReason", defaultValue: "\(gap) the \(percent) cutoff", bundle: #bundle,
                                comment: "A course's 'needs attention' reason: the score is just above a letter-grade cutoff.")
    }

    public static func justAbove() -> LocalizedStringResource {
        LocalizedStringResource("courses.health.justAbove", defaultValue: "Just above", bundle: #bundle,
                                comment: "A course health reason's gap phrase: under a tenth of a point above a goal or cutoff.")
    }

    public static func pointAbove() -> LocalizedStringResource {
        LocalizedStringResource("courses.health.pointAbove", defaultValue: "1 point above", bundle: #bundle,
                                comment: "A course health reason's gap phrase: exactly 1 point above a goal or cutoff.")
    }

    /// The placeholder is an already-formatted point value, such as "0.4" or "2.3" (never exactly 1:
    /// that is `pointAbove`, a fixed pair, the same choice L10N-03a documented for
    /// settings.threshold.pointsOne/pointsOther: `tenths` is an unrounded Double, not a clean plural
    /// count).
    public static func pointsAboveCount(_ points: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.health.pointsAboveCount", defaultValue: "\(points) points above", bundle: #bundle,
                                comment: "A course health reason's gap phrase: any other distance above a goal or cutoff.")
    }

    public static func wasDue(_ day: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.formatter.wasDue", defaultValue: "Was due \(day)", bundle: #bundle,
                                comment: "A due-date phrase for work whose due date has passed.")
    }

    public static func dueAtTime(_ day: String, _ time: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.formatter.dueAtTime", defaultValue: "Due \(day) at \(time)", bundle: #bundle,
                                comment: "A due-date phrase, within the coming week: a day and a time.")
    }

    public static func dueDay(_ day: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.formatter.dueDay", defaultValue: "Due \(day)", bundle: #bundle,
                                comment: "A due-date phrase, further out than a week: the day alone.")
    }

    /// Combines an already-formatted day and time, such as for "still accepted until Fri at 11:59 PM".
    public static func atTime(_ day: String, _ time: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.formatter.atTime", defaultValue: "\(day) at \(time)", bundle: #bundle,
                                comment: "Combines an already-formatted day and time.")
    }

    /// A course card's next-due line. 1: the assignment's title from Canvas. 2: an already-formatted
    /// due-date phrase.
    public static func cardNextDue(_ title: String, _ due: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.card.nextDue", defaultValue: "Next: \(title) \u{b7} \(due)", bundle: #bundle,
                                comment: "A course card's next-due line.")
    }

    /// A course card's combined VoiceOver label, the next-due fragment.
    public static func cardNextDueSpoken(_ title: String, _ due: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.card.nextDueSpoken", defaultValue: "next \(title), \(due)", bundle: #bundle,
                                comment: "A course card's combined VoiceOver label, the next-due fragment.")
    }

    /// VoiceOver's spoken form of a minus letter grade ("A-" read as "A minus"). The placeholder is
    /// the base letter, from Canvas, never translated.
    public static func letterMinus(_ letter: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.formatter.letterMinus", defaultValue: "\(letter) minus", bundle: #bundle,
                                comment: "VoiceOver's spoken form of a minus letter grade.")
    }

    public static func letterPlus(_ letter: String) -> LocalizedStringResource {
        LocalizedStringResource("courses.formatter.letterPlus", defaultValue: "\(letter) plus", bundle: #bundle,
                                comment: "VoiceOver's spoken form of a plus letter grade.")
    }
}

// MARK: - CourseDetail

extension L10n.CourseDetail {
    public static func unavailableTitle() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.unavailable.title", defaultValue: "Course unavailable", bundle: #bundle,
                                comment: "Course Detail: shown instead of the screen when the course is not in the latest Canvas data.")
    }

    public static func unavailableDescription() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.unavailable.description", defaultValue: "This course isn't in your latest Canvas data.",
            bundle: #bundle, comment: "Course Detail's unavailable state, body text.")
    }

    public static func navigationTitleFallback() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.navigationTitle.fallback", defaultValue: "Course", bundle: #bundle,
                                comment: "Course Detail's navigation title before the course detail has loaded.")
    }

    /// Also used by the To-Do tab's swipe action (byte-identical English, confirmed by direct
    /// comparison).
    public static func openInCanvas() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.openInCanvas", defaultValue: "Open in Canvas", bundle: #bundle,
                                comment: "Toolbar button that opens this course in the Canvas app or website.")
    }

    public static func nextDueHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.nextDueHeader", defaultValue: "Next due", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above the next due item.")
    }

    public static func recentGradesHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.recentGradesHeader", defaultValue: "Recent grades", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above recently posted grades.")
    }

    /// Also the category-weights chart's own accessibility title (byte-identical).
    public static func categoryWeightsHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.categoryWeightsHeader", defaultValue: "Category weights", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above the category-weights chart.")
    }

    public static func weightsSetByInstructor() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.weightsSetByInstructor", defaultValue: "Set by your instructor.", bundle: #bundle,
                                comment: "Course Detail, under the category-weights chart: the instructor set these weights.")
    }

    public static func weightsPointsBased() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.weightsPointsBased",
            defaultValue: "This course adds up points, so each category's share is its share of the points.",
            bundle: #bundle, comment: "Course Detail, under the category-weights chart: no instructor-set weights.")
    }

    public static func gradeDistributionHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.gradeDistributionHeader", defaultValue: "Grade distribution", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above the grade distribution.")
    }

    /// Each placeholder is an already-formatted percentage: 1 the class minimum, 2 the class
    /// maximum, 3 the class average, 4 the student's own.
    public static func gradeDistributionSentence(_ minimum: String, _ maximum: String, _ average: String, _ yours: String)
        -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.gradeDistribution.sentence",
            defaultValue: "Class range \(minimum)\u{2013}\(maximum), average \(average). You: \(yours).",
            bundle: #bundle, comment: "Course Detail's grade distribution, one sentence.")
    }

    public static func whatIfHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIfHeader", defaultValue: "What-If", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above the what-if button.")
    }

    public static func whatIfFooter() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIfFooter",
            defaultValue: "See how scores on work that isn't graded yet would change your grade. Nothing is sent to Canvas.",
            bundle: #bundle, comment: "Course Detail, under the what-if button, only when it is offered.")
    }

    public static func noAssignmentsYet() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.noAssignmentsYet", defaultValue: "No assignments in Canvas yet.", bundle: #bundle,
                                comment: "Course Detail, Assignments segment: shown when Canvas has no assignments yet.")
    }

    public static func categoriesHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.categoriesHeader", defaultValue: "Categories", bundle: #bundle,
                                comment: "Course Detail, Grades segment: section header above the category list.")
    }

    public static func currentGradeCountsGradedOnly() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.currentGradeCountsGradedOnly", defaultValue: "Current grade counts graded work only.",
            bundle: #bundle, comment: "Course Detail, Grades segment footer: the current percentage counts graded work only.")
    }

    /// One fragment in the hero's comma-joined combined VoiceOver label: lowercase, no closing
    /// period (contrast `currentGradeCountsGradedOnly`, the footer sentence; confirmed a distinct
    /// string by direct comparison, not assumed identical).
    public static func currentGradeCountsGradedOnlyFragment() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.currentGradeCountsGradedOnly.fragment", defaultValue: "current grade counts graded work only",
            bundle: #bundle, comment: "Course Detail hero's combined VoiceOver label: one joined fragment.")
    }

    public static func lettersOnlyFooter() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.lettersOnlyFooter", defaultValue: "This course shows letter grades only.", bundle: #bundle,
            comment: "Course Detail, Grades segment footer: the course shows letter grades only.")
    }

    public static func categoryNoGradesYet() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.category.noGradesYet", defaultValue: "No grades yet", bundle: #bundle,
                                comment: "Course Detail, Grades segment: a category's percentage before anything in it is graded.")
    }

    public static func categoryHidden() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.category.hidden", defaultValue: "Hidden", bundle: #bundle,
                                comment: "Course Detail, Grades segment: a category's percentage when the course shows no percentages at all.")
    }

    public static func segmentedControlAccessibilityLabel() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.segmentedControl.accessibilityLabel", defaultValue: "Show", bundle: #bundle,
                                comment: "Accessibility label of Course Detail's Overview/Assignments/Grades segmented control.")
    }

    public static func instructorsHeaderOne() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.instructorsHeaderOne", defaultValue: "Instructor", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above the instructor list, exactly one.")
    }

    public static func instructorsHeaderOther() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.instructorsHeaderOther", defaultValue: "Instructors", bundle: #bundle,
                                comment: "Course Detail, Overview: section header above the instructor list, more than one.")
    }

    public static func segmentOverview() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.segment.overview", defaultValue: "Overview", bundle: #bundle,
                                comment: "Course Detail's three segments (a segmented control).")
    }

    public static func segmentAssignments() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.segment.assignments", defaultValue: "Assignments", bundle: #bundle,
                                comment: "Course Detail's three segments (a segmented control).")
    }

    public static func segmentGrades() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.segment.grades", defaultValue: "Grades", bundle: #bundle,
                                comment: "Course Detail's three segments (a segmented control).")
    }

    public static func sectionUpcoming() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.section.upcoming", defaultValue: "Upcoming", bundle: #bundle,
                                comment: "Course Detail, Assignments segment: section header for work not yet due.")
    }

    public static func sectionMissing() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.section.missing", defaultValue: "Missing", bundle: #bundle,
                                comment: "Course Detail, Assignments segment: section header for missing work.")
    }

    public static func sectionSubmitted() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.section.submitted", defaultValue: "Submitted", bundle: #bundle,
                                comment: "Course Detail, Assignments segment: section header for submitted, ungraded work.")
    }

    public static func sectionGraded() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.section.graded", defaultValue: "Graded", bundle: #bundle,
                                comment: "Course Detail, Assignments segment: section header for graded work.")
    }

    public static func sectionPast() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.section.past", defaultValue: "Past", bundle: #bundle,
                                comment: "Course Detail, Assignments segment: section header for past work with nothing to submit.")
    }

    /// A category's (or a what-if group's) share of the course grade. The placeholder is an
    /// already-formatted percentage, such as "40%".
    public static func weightOfGrade(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.weightOfGrade", defaultValue: "\(percent) of grade", bundle: #bundle,
                                comment: "A category's (or a what-if group's) share of the course grade.")
    }

    public static func whatIfResetButton() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.resetButton", defaultValue: "Reset", bundle: #bundle,
                                comment: "The what-if sheet's toolbar button that clears every hypothetical score and weight.")
    }

    /// The placeholder is an already-localized weight phrase, such as "30% of grade" or "Points-based".
    public static func whatIfGroupHeader(_ weightText: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.groupHeader", defaultValue: "\u{2026} \u{b7} \(weightText)", bundle: #bundle,
                                comment: "The what-if sheet's section header for a category of items.")
    }

    public static func whatIfSummaryLabel() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.summaryLabel", defaultValue: "Projected", bundle: #bundle,
                                comment: "The what-if sheet's sticky summary label before the projected grade.")
    }

    public static func whatIfScoreFieldPrompt() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.scoreFieldPrompt", defaultValue: "Score", bundle: #bundle,
                                comment: "The what-if sheet's score entry field placeholder.")
    }

    public static func whatIfScoreFieldAccessibility(_ title: String, _ outOf: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.scoreFieldAccessibility", defaultValue: "Score for \(title), \(outOf)", bundle: #bundle,
            comment: "The what-if sheet's score entry field, accessibility label.")
    }

    public static func whatIfSliderAccessibility(_ title: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.sliderAccessibility", defaultValue: "Score for \(title)", bundle: #bundle,
                                comment: "The what-if sheet's score slider, accessibility label.")
    }

    /// The placeholder percent is a plain number (read as "… percent").
    public static func whatIfQuickFillAccessibility(_ title: String, _ percent: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.quickFillAccessibility", defaultValue: "Set \(title) to \(percent) percent", bundle: #bundle,
            comment: "The what-if sheet's quick-fill chip, accessibility label.")
    }

    public static func whatIfLowerByOnePoint(_ title: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.lowerByOnePoint", defaultValue: "Lower \(title) by 1 point", bundle: #bundle,
                                comment: "The what-if sheet's stepper decrement button, accessibility label.")
    }

    public static func whatIfRaiseByOnePoint(_ title: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.raiseByOnePoint", defaultValue: "Raise \(title) by 1 point", bundle: #bundle,
                                comment: "The what-if sheet's stepper increment button, accessibility label.")
    }

    public static func whatIfGoalAssignmentPicker() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.goalAssignmentPicker", defaultValue: "Assignment", bundle: #bundle,
                                comment: "The what-if sheet's goal-mode picker label: which item to solve for.")
    }

    /// The placeholder is an already-formatted whole-number percentage, such as "90%".
    public static func whatIfGoalTarget(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.goalTarget", defaultValue: "Target: \(percent)", bundle: #bundle,
                                comment: "The what-if sheet's goal-mode stepper label.")
    }

    public static func whatIfGoalHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.goalHeader", defaultValue: "Goal", bundle: #bundle,
                                comment: "The what-if sheet's goal-mode section header.")
    }

    public static func whatIfGoalFooter() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.goalFooter", defaultValue: "Other assignments keep the scores you entered above.",
            bundle: #bundle, comment: "The what-if sheet's goal-mode section footer.")
    }

    public static func whatIfGoalWorkingItOut() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.goalWorkingItOut", defaultValue: "Working it out\u{2026}", bundle: #bundle,
                                comment: "The what-if sheet's goal-mode answer before the first result has landed.")
    }

    /// The placeholder is an already-formatted whole-number percentage.
    public static func whatIfGoalAnyScoreReaches(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.goalAnyScoreReaches", defaultValue: "Any score reaches \(percent).",
                                bundle: #bundle, comment: "The what-if sheet's goal-mode answer: every score already reaches the target.")
    }

    public static func whatIfGoalMinimumOrMore(_ minimum: String, _ outOf: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.goalMinimumOrMore", defaultValue: "\(minimum)/\(outOf) or more", bundle: #bundle,
                                comment: "The what-if sheet's goal-mode answer: the lowest score that reaches the target.")
    }

    public static func whatIfGoalUnreachableEvenAtMax(_ outOf: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.goalUnreachableEvenAtMax", defaultValue: "Not reachable, even with \(outOf)/\(outOf).",
            bundle: #bundle, comment: "The what-if sheet's goal-mode answer: even the maximum score cannot reach the target.")
    }

    public static func whatIfGoalCannotChangeGrade() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.goalCannotChangeGrade", defaultValue: "This assignment can't change your grade.",
            bundle: #bundle, comment: "The what-if sheet's goal-mode answer: this item cannot change the course grade.")
    }

    public static func pointsBased() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.pointsBased", defaultValue: "Points-based", bundle: #bundle,
                                comment: "A category's (or a what-if group's) weight label when the course sums points.")
    }

    /// Maps Canvas's fixed pass/fail submission token "complete" to a localized word (§3.3
    /// "Pass/fail tokens"). Any other submission grade (a letter grade) passes through untouched.
    public static func passFailComplete() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.passFail.complete", defaultValue: "Complete", bundle: #bundle,
                                comment: "Maps Canvas's fixed pass/fail submission token 'complete' to a localized word.")
    }

    public static func passFailIncomplete() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.passFail.incomplete", defaultValue: "Incomplete", bundle: #bundle,
                                comment: "Maps Canvas's fixed pass/fail submission token 'incomplete' to a localized word.")
    }

    /// The what-if sheet's sticky summary label (an em dash separates the two clauses).
    public static func simulationLabel() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.simulationLabel", defaultValue: "Simulation \u{2014} not your real grade",
                                bundle: #bundle, comment: "The what-if sheet's sticky summary label.")
    }

    public static func whatIfWorkingItOut() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.workingItOut", defaultValue: "Projected grade: working it out",
                                bundle: #bundle, comment: "The what-if sheet's spoken summary before the first answer has landed.")
    }

    /// The placeholder is an already-formatted spoken percentage, such as "91.4".
    public static func whatIfProjected(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.projected", defaultValue: "Projected \(percent) percent", bundle: #bundle,
                                comment: "The what-if sheet's spoken summary: no baseline to compare.")
    }

    public static func whatIfProjectedSame(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.projectedSame", defaultValue: "Projected \(percent) percent, the same as your current grade",
            bundle: #bundle, comment: "The what-if sheet's spoken summary: unchanged from the current grade.")
    }

    /// 1: the projected percentage. 2: how many points higher. 3: the current percentage. All
    /// already-formatted.
    public static func whatIfProjectedUp(_ percent: String, _ points: String, _ baseline: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.projectedUp",
            defaultValue: "Projected \(percent) percent, up \(points) points from your current \(baseline) percent",
            bundle: #bundle, comment: "The what-if sheet's spoken summary: the projected grade is higher.")
    }

    public static func whatIfProjectedDown(_ percent: String, _ points: String, _ baseline: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.projectedDown",
            defaultValue: "Projected \(percent) percent, down \(points) points from your current \(baseline) percent",
            bundle: #bundle, comment: "The what-if sheet's spoken summary: the projected grade is lower.")
    }

    /// VoiceOver's spoken form of a points score ("92/100" read as "92 out of 100"). Both
    /// placeholders are already-formatted point values (§3.3 "Points and '9/10'").
    public static func scoreOutOf(_ score: String, _ possible: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.scoreOutOf", defaultValue: "\(score) out of \(possible)", bundle: #bundle,
                                comment: "VoiceOver's spoken form of a points score.")
    }

    /// The placeholder is an already-formatted day, such as "Thu" or "yesterday".
    public static func postedOn(_ day: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.postedOn", defaultValue: "Posted \(day)", bundle: #bundle,
                                comment: "Course Detail, Overview: a recently-graded item's posted day.")
    }

    /// 1: the assignment's title from Canvas. 2: the spoken score. 3: an already-formatted, spoken day.
    public static func gradedItemAccessibility(_ title: String, _ spokenScore: String, _ spokenDay: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.gradedItemAccessibility", defaultValue: "\(title), \(spokenScore), posted \(spokenDay)",
            bundle: #bundle, comment: "Course Detail, Overview: a recently-graded item's combined VoiceOver label.")
    }
}

// MARK: - Insights

extension L10n.Insights {
    public static func navigationTitle() -> LocalizedStringResource {
        LocalizedStringResource("insights.navigationTitle", defaultValue: "Insights", bundle: #bundle,
                                comment: "The Insights tab's navigation title.")
    }

    public static func emptyTitle() -> LocalizedStringResource {
        LocalizedStringResource("insights.empty.title", defaultValue: "No insights yet", bundle: #bundle,
                                comment: "Insights tab: shown before any course has graded work.")
    }

    public static func emptyDescription() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.empty.description", defaultValue: "Insights appear once your courses have graded work.",
            bundle: #bundle, comment: "Insights tab, empty state body text.")
    }

    /// Also the category-weights chart's accessibility title (byte-identical).
    public static func categoryBreakdownHeader() -> LocalizedStringResource {
        LocalizedStringResource("insights.categoryBreakdownHeader", defaultValue: "Category breakdown", bundle: #bundle,
                                comment: "Insights card header, above the category-weights chart.")
    }

    public static func categoryBreakdownSubtitle() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.categoryBreakdown.subtitle", defaultValue: "What your grades are made of, on average across your courses.",
            bundle: #bundle, comment: "Insights, under the Category breakdown header.")
    }

    /// Also the trend chart's accessibility label and Audio Graph title (byte-identical).
    public static func performanceTrendHeader() -> LocalizedStringResource {
        LocalizedStringResource("insights.performanceTrendHeader", defaultValue: "Performance trend", bundle: #bundle,
                                comment: "Insights card header, above the performance-trend chart.")
    }

    public static func performanceTrendSubtitle() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.performanceTrend.subtitle", defaultValue: "Average of your courses, from when each grade was posted.",
            bundle: #bundle, comment: "Insights, under the Performance trend header.")
    }

    public static func trendRangePicker() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.rangePicker", defaultValue: "Range", bundle: #bundle,
                                comment: "Accessibility/control label of the trend's 1M/3M/Term range picker.")
    }

    public static func trendFailed() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.failed", defaultValue: "The trend couldn't be worked out.", bundle: #bundle,
                                comment: "Insights: shown when the trend computation failed.")
    }

    public static func completionHeader() -> LocalizedStringResource {
        LocalizedStringResource("insights.completionHeader", defaultValue: "Completion", bundle: #bundle,
                                comment: "Insights card header, above the completion ring.")
    }

    public static func completionSubtitle() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.completion.subtitle", defaultValue: "Past-due work you turned in on time this term.", bundle: #bundle,
            comment: "Insights, under the Completion header.")
    }

    public static func momentumHeader() -> LocalizedStringResource {
        LocalizedStringResource("insights.momentumHeader", defaultValue: "Momentum", bundle: #bundle,
                                comment: "Insights card header, above the submission streak.")
    }

    public static func risksHeader() -> LocalizedStringResource {
        LocalizedStringResource("insights.risksHeader", defaultValue: "Needs a look", bundle: #bundle,
                                comment: "Insights card header, above the at-risk course list.")
    }

    public static func risksSubtitle() -> LocalizedStringResource {
        LocalizedStringResource("insights.risks.subtitle", defaultValue: "Courses at risk or close to a line, and why.",
                                bundle: #bundle, comment: "Insights, under the Needs a look header.")
    }

    public static func risksEmpty() -> LocalizedStringResource {
        LocalizedStringResource("insights.risks.empty", defaultValue: "Every course is on track.", bundle: #bundle,
                                comment: "Insights: shown when no course needs a look.")
    }

    public static func heavyHeader() -> LocalizedStringResource {
        LocalizedStringResource("insights.heavyHeader", defaultValue: "Heavy stretches", bundle: #bundle,
                                comment: "Insights card header, above the heavy-stretch list.")
    }

    public static func heavySubtitle() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.heavy.subtitle", defaultValue: "Two-day windows with a lot due in the next 10 days.", bundle: #bundle,
            comment: "Insights, under the Heavy stretches header.")
    }

    public static func heavyEmpty() -> LocalizedStringResource {
        LocalizedStringResource("insights.heavy.empty", defaultValue: "No heavy stretches coming up.", bundle: #bundle,
                                comment: "Insights: shown when no heavy stretch is coming up.")
    }

    public static func streakDefinition() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.streak.definition",
            defaultValue: "Days in a row, up to today, on which you submitted at least one assignment.",
            bundle: #bundle, comment: "Momentum card's stated definition of a submission streak.")
    }

    public static func streakNone() -> LocalizedStringResource {
        LocalizedStringResource("insights.streak.none", defaultValue: "No current streak", bundle: #bundle,
                                comment: "Momentum card headline: no current submission streak.")
    }

    /// A plural key: the current submission streak length (never called with 0; that is `streakNone`).
    public static func streakDays(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("insights.streak.days", defaultValue: "\(count)-day streak", bundle: #bundle,
                                comment: "Momentum card headline: the current submission streak length.")
    }

    /// The placeholder is an already-formatted whole-number percentage, such as "92%".
    public static func completionHeadline(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("insights.completion.headline", defaultValue: "\(percent) on time this term", bundle: #bundle,
                                comment: "Completion card headline.")
    }

    public static func completionDetail(_ onTime: Int, _ due: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.completion.detail", defaultValue: "\(onTime) of \(due) past-due assignments were submitted on time.",
            bundle: #bundle, comment: "Completion card detail line.")
    }

    /// 1: how many items. 2: an already-formatted date range, such as "Oct 12\u{2013}13".
    public static func heavyHeadline(_ count: Int, _ range: String) -> LocalizedStringResource {
        LocalizedStringResource("insights.heavy.headline", defaultValue: "\(count) items due \(range)", bundle: #bundle,
                                comment: "A heavy-stretch's headline.")
    }

    public static func heavyAllOneCourse() -> LocalizedStringResource {
        LocalizedStringResource("insights.heavy.allOneCourse", defaultValue: "All in one course.", bundle: #bundle,
                                comment: "A heavy-stretch's detail line when every item is in the same course.")
    }

    /// Always 2 or more courses (exactly 1 uses `heavyAllOneCourse` instead).
    public static func heavyAcrossCourses(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("insights.heavy.acrossCourses", defaultValue: "Across \(count) courses.", bundle: #bundle,
                                comment: "A heavy-stretch's detail line: the items span more than one course.")
    }

    public static func trendRangeMonth() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.range.month", defaultValue: "1M", bundle: #bundle,
                                comment: "Trend chart range picker: 1 month, abbreviated.")
    }

    public static func trendRangeQuarter() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.range.quarter", defaultValue: "3M", bundle: #bundle,
                                comment: "Trend chart range picker: 3 months, abbreviated.")
    }

    public static func trendRangeTerm() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.range.term", defaultValue: "Term", bundle: #bundle,
                                comment: "Trend chart range picker: the whole term, abbreviated.")
    }

    public static func trendRangeMonthSpoken() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.range.month.spoken", defaultValue: "Last month", bundle: #bundle,
                                comment: "Trend chart range picker's accessibility label: 1 month, spelled out.")
    }

    public static func trendRangeQuarterSpoken() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.range.quarter.spoken", defaultValue: "Last 3 months", bundle: #bundle,
                                comment: "Trend chart range picker's accessibility label: 3 months, spelled out.")
    }

    public static func trendRangeTermSpoken() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.range.term.spoken", defaultValue: "This term", bundle: #bundle,
                                comment: "Trend chart range picker's accessibility label: the whole term, spelled out.")
    }

    public static func trendNotEnoughData() -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.trend.notEnoughData", defaultValue: "Trend appears after a couple of graded assignments.",
            bundle: #bundle, comment: "Trend chart: shown until there are at least two graded data points.")
    }

    public static func trendSpanTerm() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.span.term", defaultValue: "this term", bundle: #bundle,
                                comment: "Trend summary sentence's trailing phrase for the Term range.")
    }

    public static func trendSpanMonth() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.span.month", defaultValue: "over the last month", bundle: #bundle,
                                comment: "Trend summary sentence's trailing phrase for the 1-month range.")
    }

    public static func trendSpanQuarter() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.span.quarter", defaultValue: "over the last 3 months", bundle: #bundle,
                                comment: "Trend summary sentence's trailing phrase for the 3-month range.")
    }

    /// 1: an already-formatted spoken percentage, such as "90.1 percent". 2: an already-localized
    /// span phrase, such as "this term".
    public static func trendSummarySteady(_ percent: String, _ span: String) -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.summary.steady", defaultValue: "Steady at \(percent) \(span)", bundle: #bundle,
                                comment: "Trend summary sentence: the grade did not move meaningfully.")
    }

    public static func trendSummaryUp(_ first: String, _ last: String, _ span: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.trend.summary.up", defaultValue: "Up from \(first) to \(last) \(span)", bundle: #bundle,
            comment: "Trend summary sentence: the grade moved up.")
    }

    public static func trendSummaryDown(_ first: String, _ last: String, _ span: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "insights.trend.summary.down", defaultValue: "Down from \(first) to \(last) \(span)", bundle: #bundle,
            comment: "Trend summary sentence: the grade moved down.")
    }

    public static func categoryShareAxisTitle() -> LocalizedStringResource {
        LocalizedStringResource("insights.categoryShare.axisTitle", defaultValue: "Share of grade", bundle: #bundle,
                                comment: "Audio Graph axis title for the category-breakdown chart's value axis.")
    }

    public static func categoryShareAxisCategory() -> LocalizedStringResource {
        LocalizedStringResource("insights.categoryShare.axisCategory", defaultValue: "Category", bundle: #bundle,
                                comment: "Audio Graph axis title for the category-breakdown chart's category axis.")
    }

    public static func trendAxisAverage() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.axisAverage", defaultValue: "Average of your courses", bundle: #bundle,
                                comment: "Audio Graph series name for the performance-trend chart.")
    }

    /// Distinct from `trendAxisAverage` (the longer series name): this is just the y-axis title.
    public static func trendAxisAverageShort() -> LocalizedStringResource {
        LocalizedStringResource("insights.trend.axisAverageShort", defaultValue: "Average", bundle: #bundle,
                                comment: "Audio Graph y-axis title for the performance-trend chart.")
    }

    /// A number read aloud as a percentage for VoiceOver/Audio Graphs. The placeholder is an
    /// already-formatted number.
    public static func spokenPercent(_ number: String) -> LocalizedStringResource {
        LocalizedStringResource("insights.spokenPercent", defaultValue: "\(number) percent", bundle: #bundle,
                                comment: "A number read aloud as a percentage for VoiceOver/Audio Graphs.")
    }

    public static func spokenDate() -> LocalizedStringResource {
        LocalizedStringResource("insights.spokenDate", defaultValue: "Date", bundle: #bundle,
                                comment: "Audio Graph axis title for the performance-trend chart's date axis.")
    }
}

// MARK: - To-Do

extension L10n {
    /// The To-Do tab (`TallyFeatures/ToDo`).
    public enum ToDo {
        public static func statusMissing() -> LocalizedStringResource {
            LocalizedStringResource("todo.status.missing", defaultValue: "Missing", bundle: #bundle,
                                    comment: "A To-Do item's Canvas status chip.")
        }

        public static func statusNotSubmitted() -> LocalizedStringResource {
            LocalizedStringResource("todo.status.notSubmitted", defaultValue: "Not submitted", bundle: #bundle,
                                    comment: "A To-Do item's Canvas status chip.")
        }

        public static func statusSubmitted() -> LocalizedStringResource {
            LocalizedStringResource("todo.status.submitted", defaultValue: "Submitted", bundle: #bundle,
                                    comment: "A To-Do item's Canvas status chip.")
        }

        public static func statusGraded() -> LocalizedStringResource {
            LocalizedStringResource("todo.status.graded", defaultValue: "Graded", bundle: #bundle,
                                    comment: "A To-Do item's Canvas status chip.")
        }

        public static func statusExcused() -> LocalizedStringResource {
            LocalizedStringResource("todo.status.excused", defaultValue: "Excused", bundle: #bundle,
                                    comment: "A To-Do item's Canvas status chip.")
        }

        public static func statusLate() -> LocalizedStringResource {
            LocalizedStringResource("todo.status.late", defaultValue: "Late", bundle: #bundle,
                                    comment: "A To-Do item's Canvas status chip.")
        }

        public static func sortDueDate() -> LocalizedStringResource {
            LocalizedStringResource("todo.sort.dueDate", defaultValue: "Due Date", bundle: #bundle,
                                    comment: "To-Do sort order picker option, and the picker's current-selection label.")
        }

        public static func sortPriority() -> LocalizedStringResource {
            LocalizedStringResource("todo.sort.priority", defaultValue: "Priority", bundle: #bundle,
                                    comment: "To-Do sort order picker option, and the picker's current-selection label.")
        }

        public static func sortCourse() -> LocalizedStringResource {
            LocalizedStringResource("todo.sort.course", defaultValue: "Course", bundle: #bundle,
                                    comment: "To-Do sort order picker option, and the picker's current-selection label.")
        }

        public static func priorityWord() -> LocalizedStringResource {
            LocalizedStringResource("todo.priorityWord", defaultValue: "High priority", bundle: #bundle,
                                    comment: "A To-Do item's priority flag, shown for high-priority work only.")
        }

        public static func markedDoneInTally() -> LocalizedStringResource {
            LocalizedStringResource("todo.markedDoneInTally", defaultValue: "Marked done in Tally", bundle: #bundle,
                                    comment: "Shown on a To-Do item the student marked done locally.")
        }

        public static func notSubmittedInCanvas() -> LocalizedStringResource {
            LocalizedStringResource("todo.notSubmittedInCanvas", defaultValue: "Not submitted in Canvas", bundle: #bundle,
                                    comment: "Shown on a To-Do item marked done locally while Canvas still expects a submission.")
        }

        public static func sectionMissingOverdue() -> LocalizedStringResource {
            LocalizedStringResource("todo.section.missingOverdue", defaultValue: "Missing & overdue", bundle: #bundle,
                                    comment: "To-Do section header: missing and overdue work.")
        }

        public static func sectionDueThisWeek() -> LocalizedStringResource {
            LocalizedStringResource("todo.section.dueThisWeek", defaultValue: "Due this week", bundle: #bundle,
                                    comment: "To-Do section header: work due within 7 days.")
        }

        public static func sectionDueLater() -> LocalizedStringResource {
            LocalizedStringResource("todo.section.dueLater", defaultValue: "Due later", bundle: #bundle,
                                    comment: "To-Do section header: work due later than 7 days out.")
        }

        public static func stillAcceptedUntil(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("todo.stillAcceptedUntil", defaultValue: "Still accepted until \(time)", bundle: #bundle,
                                    comment: "A To-Do item's late note: missing, but Canvas still accepts it until this time.")
        }

        public static func stillAccepted() -> LocalizedStringResource {
            LocalizedStringResource("todo.stillAccepted", defaultValue: "Still accepted", bundle: #bundle,
                                    comment: "A To-Do item's late note: missing, but Canvas still accepts it, no lock date.")
        }

        public static func closedTalkToInstructor() -> LocalizedStringResource {
            LocalizedStringResource(
                "todo.closedTalkToInstructor", defaultValue: "Closed \u{2014} talk to your instructor", bundle: #bundle,
                comment: "A To-Do item's late note: the lock date has passed.")
        }

        public static func navigationTitle() -> LocalizedStringResource {
            LocalizedStringResource("todo.navigationTitle", defaultValue: "To-Do", bundle: #bundle,
                                    comment: "The To-Do tab's navigation title.")
        }

        public static func sortByLabel() -> LocalizedStringResource {
            LocalizedStringResource("todo.sortByLabel", defaultValue: "Sort by", bundle: #bundle,
                                    comment: "To-Do toolbar menu's control label.")
        }

        public static func sortMenuLabel() -> LocalizedStringResource {
            LocalizedStringResource("todo.sortMenuLabel", defaultValue: "Sort", bundle: #bundle,
                                    comment: "To-Do toolbar button that opens the sort-order menu.")
        }

        public static func selectModeCancel() -> LocalizedStringResource {
            LocalizedStringResource("todo.selectMode.cancel", defaultValue: "Cancel", bundle: #bundle,
                                    comment: "To-Do toolbar button: leaves multi-select mode.")
        }

        public static func selectModeSelect() -> LocalizedStringResource {
            LocalizedStringResource("todo.selectMode.select", defaultValue: "Select", bundle: #bundle,
                                    comment: "To-Do toolbar button: enters multi-select mode.")
        }

        public static func markDoneButton() -> LocalizedStringResource {
            LocalizedStringResource("todo.markDoneButton", defaultValue: "Mark Done", bundle: #bundle,
                                    comment: "To-Do's bottom-bar button that marks every selected item done.")
        }

        public static func swipeNotDone() -> LocalizedStringResource {
            LocalizedStringResource("todo.swipe.notDone", defaultValue: "Not Done", bundle: #bundle,
                                    comment: "To-Do row swipe action: un-marks a done item.")
        }

        public static func swipeDone() -> LocalizedStringResource {
            LocalizedStringResource("todo.swipe.done", defaultValue: "Done", bundle: #bundle,
                                    comment: "To-Do row swipe action: marks an item done.")
        }

        public static func loading() -> LocalizedStringResource {
            LocalizedStringResource("todo.loading", defaultValue: "Loading your work\u{2026}", bundle: #bundle,
                                    comment: "To-Do tab: shown while the first projection is loading.")
        }

        public static func emptyTitle() -> LocalizedStringResource {
            LocalizedStringResource("todo.empty.title", defaultValue: "You're all caught up", bundle: #bundle,
                                    comment: "To-Do tab: shown when nothing is missing or due.")
        }

        public static func emptyDescription() -> LocalizedStringResource {
            LocalizedStringResource("todo.empty.description", defaultValue: "Nothing is missing, and nothing is due.",
                                    bundle: #bundle, comment: "To-Do tab, empty state body text.")
        }

        /// The placeholder is the assignment's title from Canvas, never translated.
        public static func markDoneAccessibility(_ title: String) -> LocalizedStringResource {
            LocalizedStringResource("todo.markDone.accessibility", defaultValue: "Mark \(title) done", bundle: #bundle,
                                    comment: "To-Do row's completion control, accessibility label when not yet done.")
        }

        public static func markedDoneAccessibility(_ title: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "todo.markedDone.accessibility", defaultValue: "Marked done. Mark \(title) not done", bundle: #bundle,
                comment: "To-Do row's completion control, accessibility label when already done.")
        }
    }
}

// MARK: - TallyPlatform: generic notification content

extension L10n {
    /// Generic (no student content) notification defaults (`TallyPlatform/UNNotificationScheduler.swift`;
    /// security.md §3.3: never a course, assignment or grade on the Lock Screen by default). The app
    /// layer injects its own snapshot-backed resolver; this is what shows until then, or if that
    /// resolver is absent.
    public enum Notifications {
        public static func dueTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.due.title", defaultValue: "Due soon", bundle: #bundle,
                                    comment: "Generic notification title: work is due soon.")
        }

        public static func dueBody() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.due.body", defaultValue: "Open Tally to see what's due.",
                                    bundle: #bundle, comment: "Generic notification body: work is due soon.")
        }

        public static func followupTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.followup.title", defaultValue: "Still to do", bundle: #bundle,
                                    comment: "Generic notification title: a follow-up reminder for still-missing work.")
        }

        public static func followupBody() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.followup.body", defaultValue: "Open Tally to see what's left.",
                                    bundle: #bundle, comment: "Generic notification body: a follow-up reminder.")
        }

        public static func examTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.exam.title", defaultValue: "Exam coming up", bundle: #bundle,
                                    comment: "Generic notification title: an exam is coming up.")
        }

        public static func examBody() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.exam.body", defaultValue: "Open Tally for the details.",
                                    bundle: #bundle, comment: "Generic notification body: an exam is coming up.")
        }

        public static func digestTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.digest.title", defaultValue: "What changed", bundle: #bundle,
                                    comment: "Generic notification title: a change digest.")
        }

        public static func digestBody() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.digest.body", defaultValue: "Open Tally to see your updates.",
                                    bundle: #bundle, comment: "Generic notification body: a change digest.")
        }

        public static func weekAheadTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.weekAhead.title", defaultValue: "Your week ahead", bundle: #bundle,
                                    comment: "Generic notification title: the week-ahead summary.")
        }

        public static func weekAheadBody() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.weekAhead.body", defaultValue: "Open Tally to plan your week.",
                                    bundle: #bundle, comment: "Generic notification body: the week-ahead summary.")
        }

        public static func gradePostedTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.gradePosted.title", defaultValue: "New grade posted", bundle: #bundle,
                                    comment: "Generic notification title: a new grade was posted (never the grade itself, R10).")
        }

        public static func gradePostedBody() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.gradePosted.body", defaultValue: "Open Tally to see it.",
                                    bundle: #bundle, comment: "Generic notification body: a new grade was posted.")
        }

        public static func belowGoalTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.belowGoal.title", defaultValue: "Below your goal", bundle: #bundle,
                                    comment: "Generic notification title: a course dropped below the student's goal.")
        }

        public static func belowGoalBody() -> LocalizedStringResource {
            LocalizedStringResource(
                "notifications.generic.belowGoal.body", defaultValue: "Open Tally to see where you stand.", bundle: #bundle,
                comment: "Generic notification body: a course dropped below the student's goal.")
        }

        public static func sentinelTitle() -> LocalizedStringResource {
            LocalizedStringResource("notifications.generic.sentinel.title", defaultValue: "Tally hasn't refreshed", bundle: #bundle,
                                    comment: "Generic notification title: Tally has not refreshed in a while.")
        }

        public static func sentinelBody() -> LocalizedStringResource {
            LocalizedStringResource(
                "notifications.generic.sentinel.body", defaultValue: "Open Tally to update your data.", bundle: #bundle,
                comment: "Generic notification body: Tally has not refreshed in a while.")
        }

        public static func hiddenPreviewPlaceholder() -> LocalizedStringResource {
            LocalizedStringResource(
                "notifications.category.hiddenPreviewPlaceholder", defaultValue: "Tally reminder", bundle: #bundle,
                comment: "What the system shows instead of the body when Show Previews is off, or the device is locked.")
        }
    }
}
