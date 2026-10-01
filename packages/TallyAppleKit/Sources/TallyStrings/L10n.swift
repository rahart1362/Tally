import Foundation

/// Every user-facing string the app, the widget and the intents share (plan 08 §3.1, L10N-01).
///
/// Each entry is a `LocalizedStringResource` with a semantic key, the English text as its
/// `defaultValue`, a translator comment, and `bundle: #bundle`: this target's resource bundle,
/// which holds `Resources/Localizable.xcstrings`. The catalog is the source of truth for the text
/// (`scripts/ci/check_string_catalogs.py` checks that every key used here is in it, and that
/// every English value, translation and plural form has the same placeholders). The
/// `defaultValue` is only the fallback when a lookup finds nothing.
///
/// Why wrappers: Xcode 26 generates symbols for catalog keys, but they are internal to this
/// target, so the other targets reach the strings through these public functions.
///
/// How to add a string: add the key to the catalog (English value, comment, plural variants
/// where a count is involved), then a function here returning the resource. Views take it as
/// `Text(L10n.Area.name(...))`; code that needs a `String` (accessibility labels built from parts,
/// notification bodies, share text) uses `String(localized:)`. Canvas content (course names,
/// assignment titles, letter grades) is never localized: pass it with `Text(verbatim:)`.
///
/// Default isolation (nonisolated), deliberately: SwiftPM's generated resource accessor declares
/// a class, and under `.defaultIsolation(MainActor.self)` it gained an isolated deinit (plan 06 A2,
/// CI run 36390172728). The functions are pure, so main-actor and background callers alike use
/// them.
public enum L10n {
    /// The Dashboard (`TallyFeatures/Dashboard`).
    public enum Dashboard {
        /// The hero's caption: "Average of 1 course", "Average of 5 courses". A plural key: the
        /// catalog holds one form per plural category of each language.
        public static func averageOfCourses(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.averageOfCourses",
                defaultValue: "Average of \(count) courses",
                bundle: #bundle,
                comment: "Dashboard hero caption above the average percentage. The number is how many courses are in the average."
            )
        }

        /// Plan 08 G-5 (XG-03): the hero's second caption, "2 courses not included", when some
        /// courses are left out of the average. A plural key.
        public static func coursesNotIncluded(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.notIncluded", defaultValue: "\(count) courses not included", bundle: #bundle,
                comment: "Dashboard hero, under the average: how many courses are left out of the average (no grade in Canvas yet, letters only, hidden by the instructor, or grades kept outside Canvas). An info button follows it.")
        }

        /// The info button after "2 courses not included" (VoiceOver reads it).
        public static func notIncludedButton() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.notIncluded.button", defaultValue: "About the courses not included", bundle: #bundle,
                comment: "VoiceOver label of the info button after 'N courses not included' on the Dashboard hero. It opens a list of those courses and why each is left out.")
        }

        /// The title of the list of courses left out of the average.
        public static func notIncludedTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.notIncluded.title", defaultValue: "Not in your average", bundle: #bundle,
                comment: "Title of the bubble that lists the courses left out of the Dashboard's average, each with the reason.")
        }

        /// Plan 08 G-5: the hero's caption when no course can be averaged and the school does not
        /// appear to keep grades in Canvas (the numeral is a dash).
        public static func heroNotInCanvas() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.notInCanvas", defaultValue: "Grades aren't in Canvas", bundle: #bundle,
                comment: "Dashboard hero caption when the student's school does not appear to keep grades in Canvas, so there is no average to show. An info button follows it.")
        }

        /// The info button after "Grades aren't in Canvas" on the hero (VoiceOver reads it).
        public static func notInCanvasButton() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.notInCanvas.button", defaultValue: "About grades not in Canvas", bundle: #bundle,
                comment: "VoiceOver label of the info button after 'Grades aren't in Canvas' on the Dashboard hero.")
        }

        /// The hero with nothing to average yet (the text the hero showed before plan 08).
        public static func noGradesYet() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.hero.noGrades", defaultValue: "No grades to show yet", bundle: #bundle,
                                    comment: "Dashboard hero when no course has a grade to average yet.")
        }

        /// Why a course is left out of the average: Canvas sent a letter but no percentage.
        public static func reasonNoPercentage() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.reason.noPercentage", defaultValue: "No percentage in Canvas", bundle: #bundle,
                comment: "In the list of courses left out of the Dashboard's average: Canvas shows this course's grade without a percentage to average.")
        }

        /// Why a course is left out of the average: it shows letter grades only.
        public static func reasonLettersOnly() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.reason.lettersOnly", defaultValue: "Letter grades only", bundle: #bundle,
                comment: "In the list of courses left out of the Dashboard's average: the course shows letter grades, not percentages.")
        }

        /// Why a course is left out of the average: the instructor hides the course total.
        public static func reasonHiddenByInstructor() -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.reason.hiddenByInstructor", defaultValue: "Hidden by your instructor", bundle: #bundle,
                comment: "In the list of courses left out of the Dashboard's average: the instructor hides the course's total grade.")
        }
    }

    /// Plan 08 §4.5 (XG-03): grades kept outside Canvas, everywhere a grade is shown. The G-4 copy
    /// the owner approved on 2026-09-30, plus the existing "No grade yet" phrases these screens
    /// share.
    public enum Grades {
        /// Where a course's grade goes when Canvas has posted none yet; also a course health status.
        public static func noGradeYet() -> LocalizedStringResource {
            LocalizedStringResource("grades.noGradeYet", defaultValue: "No grade yet", bundle: #bundle,
                                    comment: "Shown where a course's grade goes when Canvas has posted no grade yet. Also a course status.")
        }

        public static func hiddenByInstructor() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.hidden.instructor", defaultValue: "Your instructor has hidden course totals.", bundle: #bundle,
                comment: "Why a course shows no grade: the instructor hides the course total in Canvas.")
        }

        public static func notPostedYet() -> LocalizedStringResource {
            LocalizedStringResource("grades.hidden.notPosted", defaultValue: "No grade has been posted yet.", bundle: #bundle,
                                    comment: "Why a course shows no grade: Canvas has no posted grade for it yet.")
        }

        /// The caption under the dash that stands for a grade kept outside Canvas.
        public static func notInCanvasCaption() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.notInCanvas.caption", defaultValue: "Not in Canvas", bundle: #bundle,
                comment: "Short caption under a dash shown instead of a course grade, when the school does not appear to enter this course's grades into Canvas.")
        }

        /// What VoiceOver reads for that dash (never "dash"), and the course status chip.
        public static func notInCanvasStatus() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.notInCanvas.status", defaultValue: "Grade not in Canvas", bundle: #bundle,
                comment: "A course's status, and what VoiceOver reads for the dash shown instead of its grade: the school does not appear to enter this course's grades into Canvas.")
        }

        /// The caption under the dash for a course with no graded work in Canvas (advisory, homeroom).
        public static func notGradedCaption() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.notGradedInCanvas.caption", defaultValue: "Not graded in Canvas", bundle: #bundle,
                comment: "Short caption under a dash shown instead of a course grade, for a course with no graded work in Canvas (such as advisory or homeroom).")
        }

        public static func notGradedDetail() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.notGradedInCanvas.detail", defaultValue: "This course doesn't have graded work in Canvas.", bundle: #bundle,
                comment: "Explains why a course (such as advisory or homeroom) shows no grade: it has no graded work in Canvas.")
        }

        /// The info bubble's title (the header).
        public static func infoTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.info.title", defaultValue: "Grades aren't in Canvas", bundle: #bundle,
                comment: "Title of the info bubble explaining that the student's school does not appear to enter grades into Canvas.")
        }

        public static func infoBodyCourse() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.info.body.course",
                defaultValue: "Your school doesn't appear to enter grades for this course into Canvas, so Tally can't show them. Your assignments, due dates and reminders still work. Check your school's grade portal for this grade.",
                bundle: #bundle,
                comment: "Info bubble body for one course whose grades the school does not appear to enter into Canvas. 'Grade portal' is the school's own grading website or app.")
        }

        public static func infoBodySchool() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.info.body.school",
                defaultValue: "Your school doesn't appear to enter your grades directly into Canvas. Tally can show only grades that are posted in Canvas. Your assignments, due dates and reminders still work. If you'd like to see your grades in Tally, you can let your school know.",
                bundle: #bundle,
                comment: "Info bubble body when none of the student's courses appear to have grades in Canvas. It leads to the 'Tell My School' button.")
        }

        /// The share action (a `ShareLink`), as onboarding's "Ask My School".
        public static func tellMySchool() -> LocalizedStringResource {
            LocalizedStringResource("grades.info.tellMySchool", defaultValue: "Tell My School", bundle: #bundle,
                                    comment: "Button that opens the share sheet with a message the student can send to their school, asking it to enter grades in Canvas.")
        }

        /// The message the student shares with the school (G-4: no link, no price claim).
        public static func shareText(school: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.info.shareText",
                defaultValue: "Hello, I'm a student at \(school). I use Canvas to keep track of my assignments, but my grades don't appear there. Would the school consider entering grades in Canvas too? I could then see my grades next to my work, in Canvas and in apps I use with it, like Tally. Thank you.",
                bundle: #bundle,
                comment: "A message the student sends to their school from the share sheet, in the student's own voice. The placeholder is the school's name. Keep it free of links and prices.")
        }

        /// The same message when Tally has no school name (sample data, or no name on record).
        public static func shareTextNoSchool() -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.info.shareText.noSchool",
                defaultValue: "Hello, I'm a student at your school. I use Canvas to keep track of my assignments, but my grades don't appear there. Would the school consider entering grades in Canvas too? I could then see my grades next to my work, in Canvas and in apps I use with it, like Tally. Thank you.",
                bundle: #bundle,
                comment: "The same message the student sends to their school, used when the school's name is not known. Keep it free of links and prices.")
        }

        /// The ⓘ button's VoiceOver label: "About grades for ENG-10".
        public static func infoButton(courseCode: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "grades.info.button", defaultValue: "About grades for \(courseCode)", bundle: #bundle,
                comment: "VoiceOver label of the info button next to a course whose grades are not in Canvas. The placeholder is the course code from Canvas, such as 'ENG-10'.")
        }
    }

    /// The Courses tab (`TallyFeatures/Courses`).
    public enum Courses {
        public static func healthOnTrack() -> LocalizedStringResource {
            LocalizedStringResource("courses.health.onTrack", defaultValue: "On track", bundle: #bundle,
                                    comment: "A course's status chip: nothing needs the student's attention.")
        }

        public static func healthNeedsAttention() -> LocalizedStringResource {
            LocalizedStringResource("courses.health.needsAttention", defaultValue: "Needs attention", bundle: #bundle,
                                    comment: "A course's status chip: missing work, or the grade is close to a cutoff.")
        }

        public static func healthAtRisk() -> LocalizedStringResource {
            LocalizedStringResource("courses.health.atRisk", defaultValue: "At risk", bundle: #bundle,
                                    comment: "A course's status chip: several missing items, or the grade is well below the goal.")
        }
    }

    /// Course Detail (`TallyFeatures/CourseDetail`).
    public enum CourseDetail {
        /// Plan 08 §4.4 row 5: "Recent grades" (and the Grades segment) for a course whose grades
        /// are kept outside Canvas.
        public static func notInCanvasLine() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.notInCanvas.line", defaultValue: "Grades for this course aren't in Canvas.", bundle: #bundle,
                comment: "Course Detail, in place of the recent grades and the category percentages, when the school does not appear to enter this course's grades into Canvas.")
        }

        public static func whatIfButton() -> LocalizedStringResource {
            LocalizedStringResource("courseDetail.whatIf.button", defaultValue: "Try What-If Scores", bundle: #bundle,
                                    comment: "Button that opens the what-if calculator, where the student tries scores on work that isn't graded yet.")
        }

        /// Plan 08 §4.4 row 6: why the what-if is disabled for a course whose grades are kept
        /// outside Canvas (G-4).
        public static func whatIfNotInCanvas() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.notInCanvas",
                defaultValue: "What-if needs grades in Canvas, and this course's grades don't appear to be kept there.",
                bundle: #bundle,
                comment: "Under the disabled what-if button: the what-if calculator works from Canvas grades, and this course's grades are not in Canvas.")
        }

        public static func whatIfHiddenTotals() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.hiddenTotals", defaultValue: "What-if isn't available: your instructor has hidden course totals.",
                bundle: #bundle, comment: "Why the what-if calculator is not offered: the instructor hides the course total in Canvas.")
        }

        public static func whatIfNoGradePosted() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.noGradePosted", defaultValue: "What-if isn't available: no grade has been posted yet.",
                bundle: #bundle, comment: "Why the what-if calculator is not offered: a letter-grade course with no grade posted yet.")
        }

        public static func whatIfLettersOnly() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.lettersOnly", defaultValue: "What-if isn't available for a course that shows letter grades only.",
                bundle: #bundle, comment: "Why the what-if calculator is not offered: the course shows letter grades, not percentages.")
        }

        public static func whatIfNothingToTry() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.nothingToTry", defaultValue: "Everything in this course has a score, so there is nothing to try.",
                bundle: #bundle, comment: "Why the what-if calculator is not offered: every assignment already has a score.")
        }
    }

    /// Insights (`TallyFeatures/Insights`).
    public enum Insights {
        /// Plan 08 §4.4 row 7: the trend's empty state when no course qualifies because the
        /// grades are kept outside Canvas.
        public static func trendNotInCanvas() -> LocalizedStringResource {
            LocalizedStringResource(
                "insights.trend.notInCanvas", defaultValue: "Trends appear when grades are posted in Canvas.", bundle: #bundle,
                comment: "Insights, in place of the performance trend chart, when the student's grades are not in Canvas.")
        }
    }

    /// The widgets (`TallyGlance`).
    public enum Glance {
        /// The Standing widget when the student has not chosen to show grades in widgets (PMO R10).
        public static func standingHiddenTitle() -> LocalizedStringResource {
            LocalizedStringResource("glance.standing.hidden.title", defaultValue: "Grades are hidden", bundle: #bundle,
                                    comment: "Standing widget title when the student has not chosen to show grades in widgets.")
        }

        public static func standingHiddenDetail() -> LocalizedStringResource {
            LocalizedStringResource(
                "glance.standing.hidden.detail", defaultValue: "They appear here only if you choose to show grades in widgets.",
                bundle: #bundle, comment: "Standing widget, under 'Grades are hidden': how to show grades in the widget.")
        }

        /// Plan 08 §4.4 row 14: opted in, but no course has a grade to average yet.
        public static func standingNoneYetTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "glance.standing.noneYet.title", defaultValue: "No grades yet", bundle: #bundle,
                comment: "Standing widget title when the student chose to show grades in widgets, but no course has a grade to average yet.")
        }

        public static func standingNoneYetDetail() -> LocalizedStringResource {
            LocalizedStringResource("glance.standing.noneYet.detail",
                                    defaultValue: "Your average appears here once grades are posted in Canvas.",
                                    bundle: #bundle, comment: "Standing widget, under 'No grades yet'.")
        }

        /// Plan 08 §4.4 row 14 and §4.5: opted in, and the school does not appear to keep grades in Canvas.
        public static func standingNotInCanvasTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "glance.standing.notInCanvas.title", defaultValue: "Grades aren't in Canvas", bundle: #bundle,
                comment: "Standing widget title when the student's school does not appear to keep grades in Canvas (it uses another grading system).")
        }

        public static func standingNotInCanvasDetail() -> LocalizedStringResource {
            LocalizedStringResource("glance.standing.notInCanvas.detail",
                                    defaultValue: "Your school doesn't appear to post grades there.", bundle: #bundle,
                                    comment: "Standing widget, under 'Grades aren't in Canvas'. 'There' is Canvas.")
        }
    }
}
