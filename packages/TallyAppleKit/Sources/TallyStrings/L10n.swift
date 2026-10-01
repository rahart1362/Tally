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

    /// Plan 08 §5 L10N-03a: text shared across more than one screen area.
    public enum Account {
        /// The destructive button that signs out and erases local data. Shared by the lock screen
        /// (`LockView`, with no device passcode) and Settings.
        public static func signOutAndErase() -> LocalizedStringResource {
            LocalizedStringResource("account.signOutAndErase", defaultValue: "Sign Out & Erase", bundle: #bundle,
                                    comment: "Destructive button that signs the student out and erases Tally's local data. Shown on the lock screen (when there is no device passcode) and in Settings.")
        }

        /// The primary entry action. Shared by `WelcomeView` and onboarding's "Ask My School"
        /// (`SchoolNotEnabledView`, after a school search finds no enabled school).
        public static func findMySchool() -> LocalizedStringResource {
            LocalizedStringResource("account.findMySchool", defaultValue: "Find My School", bundle: #bundle,
                                    comment: "Primary button that starts the school search, to sign in with Canvas.")
        }

        /// The secondary entry action, offered without signing in. Shared by `WelcomeView` and
        /// `SchoolNotEnabledView`.
        public static func exploreWithSampleData() -> LocalizedStringResource {
            LocalizedStringResource("account.exploreWithSampleData", defaultValue: "Explore with Sample Data", bundle: #bundle,
                                    comment: "Secondary button that opens Tally in sample-data mode, without signing in.")
        }

        /// The app-store-compliance.md R10 non-affiliation disclaimer. Shared by `WelcomeView`'s
        /// footer and Settings' about section.
        public static func disclaimer() -> LocalizedStringResource {
            LocalizedStringResource(
                "account.disclaimer",
                defaultValue: "Tally is an independent app and is not affiliated with, endorsed by, or sponsored by Instructure, Inc. Canvas is a trademark of Instructure, Inc.",
                bundle: #bundle,
                comment: "The required non-affiliation disclaimer (app-store-compliance.md R10). 'Instructure, Inc.' and 'Canvas' are proper nouns and stay as written.")
        }

        /// A toolbar dismiss button. Shared by Settings and other sheets.
        public static func done() -> LocalizedStringResource {
            LocalizedStringResource("account.done", defaultValue: "Done", bundle: #bundle,
                                    comment: "Dismiss button for a sheet.")
        }
    }

    /// The app lock (`TallyFeatures/Lock`; SEC-07, ADR 0001).
    public enum Lock {
        /// The Face ID / Touch ID / passcode authentication reason the system shows when unlocking.
        public static func unlockReason() -> LocalizedStringResource {
            LocalizedStringResource(
                "lock.unlockReason", defaultValue: "Unlock Tally to see your courses and grades.", bundle: #bundle,
                comment: "The reason text the system's Face ID/Touch ID/passcode prompt shows when the student unlocks Tally's app lock.")
        }

        /// The authentication reason the system shows when turning the app lock off in Settings.
        public static func disableReason() -> LocalizedStringResource {
            LocalizedStringResource("lock.disableReason", defaultValue: "Turn off the Tally app lock.", bundle: #bundle,
                                    comment: "The reason text the system's Face ID/Touch ID/passcode prompt shows when the student turns off Tally's app lock in Settings.")
        }

        /// The lock screen's title, under the Tally mark.
        public static func title() -> LocalizedStringResource {
            LocalizedStringResource("lock.title", defaultValue: "Tally is locked", bundle: #bundle,
                                    comment: "Lock screen title, shown under the Tally mark while the app is locked.")
        }

        /// Shown instead of the unlock button when the iPhone has no device passcode: the lock can
        /// never open, so sign-out and erase is the only way out (security.md §3.3).
        public static func passcodeNotSetMessage() -> LocalizedStringResource {
            LocalizedStringResource(
                "lock.passcodeNotSet.message",
                defaultValue: "Set a device passcode in Settings to unlock Tally, or sign out and erase Tally's data from this iPhone.",
                bundle: #bundle,
                comment: "Lock screen message shown when the iPhone has no device passcode, so the app lock can never be unlocked. Only Sign Out & Erase is offered.")
        }

        public static func unlockWithFaceID() -> LocalizedStringResource {
            LocalizedStringResource("lock.unlock.faceID", defaultValue: "Unlock with Face ID", bundle: #bundle,
                                    comment: "Lock screen's unlock button, when Face ID is the available biometric.")
        }

        public static func unlockWithTouchID() -> LocalizedStringResource {
            LocalizedStringResource("lock.unlock.touchID", defaultValue: "Unlock with Touch ID", bundle: #bundle,
                                    comment: "Lock screen's unlock button, when Touch ID is the available biometric.")
        }

        public static func unlockWithOpticID() -> LocalizedStringResource {
            LocalizedStringResource("lock.unlock.opticID", defaultValue: "Unlock with Optic ID", bundle: #bundle,
                                    comment: "Lock screen's unlock button, when Optic ID is the available biometric.")
        }

        public static func unlockWithPasscode() -> LocalizedStringResource {
            LocalizedStringResource("lock.unlock.passcode", defaultValue: "Unlock with Passcode", bundle: #bundle,
                                    comment: "Lock screen's unlock button, when no biometric is enrolled but a device passcode is set.")
        }

        /// Shown briefly while availability is still unknown (before the first availability check).
        public static func unlockGeneric() -> LocalizedStringResource {
            LocalizedStringResource("lock.unlock.generic", defaultValue: "Unlock", bundle: #bundle,
                                    comment: "Lock screen's unlock button before Tally has checked which authentication method is available.")
        }

        // MARK: Settings' App Lock rows (`AppLockSettingsModel`)

        public static func settingsTitle() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.title", defaultValue: "App Lock", bundle: #bundle,
                                    comment: "Settings toggle: turns the app lock on or off.")
        }

        /// The placeholder is the credential words (`credentialFaceID` etc).
        public static func footerAsks(_ credential: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "lock.settings.footer.asks",
                defaultValue: "Tally asks for \(credential) when it opens, and after it has been in the background longer than the time you choose.",
                bundle: #bundle,
                comment: "Settings, App Lock footer: what unlocking asks for and when. The placeholder names the credential, such as 'Face ID or your passcode'.")
        }

        public static func footerPasscodeNotSetLockOn() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.footer.passcodeNotSet.lockOn", defaultValue: "Set a passcode for this iPhone, or sign out.", bundle: #bundle,
                                    comment: "Settings, App Lock footer: the lock is on but the device passcode was removed, so it can never unlock.")
        }

        public static func footerPasscodeNotSetLockOff() -> LocalizedStringResource {
            LocalizedStringResource(
                "lock.settings.footer.passcodeNotSet.lockOff", defaultValue: "To use App Lock, set a passcode for this iPhone in the Settings app.", bundle: #bundle,
                comment: "Settings, App Lock footer: the device has no passcode, so the toggle is disabled.")
        }

        public static func footerUnavailable() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.footer.unavailable", defaultValue: "App Lock isn't available on this iPhone right now.", bundle: #bundle,
                                    comment: "Settings, App Lock footer: the device cannot authenticate for a reason other than a missing passcode.")
        }

        public static func graceImmediately() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.grace.immediately", defaultValue: "Immediately", bundle: #bundle,
                                    comment: "Require Unlock picker option: locks as soon as Tally leaves the foreground.")
        }

        public static func graceOneMinute() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.grace.oneMinute", defaultValue: "After 1 minute", bundle: #bundle,
                                    comment: "Require Unlock picker option.")
        }

        public static func graceFiveMinutes() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.grace.fiveMinutes", defaultValue: "After 5 minutes", bundle: #bundle,
                                    comment: "Require Unlock picker option.")
        }

        public static func graceFifteenMinutes() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.grace.fifteenMinutes", defaultValue: "After 15 minutes", bundle: #bundle,
                                    comment: "Require Unlock picker option.")
        }

        public static func credentialFaceID() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.credential.faceID", defaultValue: "Face ID or your passcode", bundle: #bundle,
                                    comment: "Names what unlocking App Lock asks for, inside a longer sentence.")
        }

        public static func credentialTouchID() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.credential.touchID", defaultValue: "Touch ID or your passcode", bundle: #bundle,
                                    comment: "Names what unlocking App Lock asks for, inside a longer sentence.")
        }

        public static func credentialOpticID() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.credential.opticID", defaultValue: "Optic ID or your passcode", bundle: #bundle,
                                    comment: "Names what unlocking App Lock asks for, inside a longer sentence.")
        }

        public static func credentialPasscodeOnly() -> LocalizedStringResource {
            LocalizedStringResource("lock.settings.credential.passcodeOnly", defaultValue: "your passcode", bundle: #bundle,
                                    comment: "Names what unlocking App Lock asks for (no biometric enrolled), inside a longer sentence.")
        }
    }

    /// Reminders (`TallyFeatures/Reminders`; ux-ui.md §3.2 stage 6, §3.7.7).
    public enum Reminders {
        public static func tipTitle() -> LocalizedStringResource {
            LocalizedStringResource("reminders.tip.title", defaultValue: "Get reminded before work is due", bundle: #bundle,
                                    comment: "Dashboard reminders tip card title.")
        }

        public static func tipBody() -> LocalizedStringResource {
            LocalizedStringResource(
                "reminders.tip.body", defaultValue: "Tally can remind you a day and an hour before each deadline.", bundle: #bundle,
                comment: "Dashboard reminders tip card body.")
        }

        public static func turnOn() -> LocalizedStringResource {
            LocalizedStringResource("reminders.turnOn", defaultValue: "Turn On Reminders", bundle: #bundle,
                                    comment: "Button that requests the notifications permission.")
        }

        public static func notNow() -> LocalizedStringResource {
            LocalizedStringResource("reminders.notNow", defaultValue: "Not Now", bundle: #bundle,
                                    comment: "VoiceOver label for the reminders tip card's dismiss button.")
        }

        public static func sectionTitle() -> LocalizedStringResource {
            LocalizedStringResource("reminders.sectionTitle", defaultValue: "Reminders", bundle: #bundle,
                                    comment: "Settings section header and row title for reminders.")
        }

        public static func denied() -> LocalizedStringResource {
            LocalizedStringResource("reminders.denied", defaultValue: "Notifications are off for Tally", bundle: #bundle,
                                    comment: "Settings: the notifications permission was denied.")
        }

        public static func openSettings() -> LocalizedStringResource {
            LocalizedStringResource("reminders.openSettings", defaultValue: "Open Settings", bundle: #bundle,
                                    comment: "Button that opens Tally's notification settings in the iOS Settings app.")
        }

        public static func sampleData() -> LocalizedStringResource {
            LocalizedStringResource(
                "reminders.sampleData",
                defaultValue: "Reminders aren't scheduled for sample data. Sign in with your school's Canvas to be reminded before work is due.",
                bundle: #bundle,
                comment: "Settings: reminders are not available in sample mode.")
        }

        public static func hideCourseNames() -> LocalizedStringResource {
            LocalizedStringResource("reminders.hideCourseNames", defaultValue: "Hide Course Names", bundle: #bundle,
                                    comment: "Settings toggle: notifications say 'a course'/'An assignment' instead of names (PMO R10).")
        }

        public static func footer() -> LocalizedStringResource {
            LocalizedStringResource(
                "reminders.footer",
                defaultValue: "A day and an hour before each due date, and an evening and a Sunday summary when work is due. Nothing arrives between 11 PM and 7 AM: a reminder comes earlier instead. Reminders use the Canvas data Tally last refreshed, and Tally tells you if it hasn't refreshed for a day.",
                bundle: #bundle,
                comment: "Settings, Reminders section footer: when reminders arrive.")
        }

        public static func hideCourseNamesFooter() -> LocalizedStringResource {
            LocalizedStringResource(
                "reminders.hideCourseNamesFooter",
                defaultValue: "With Hide Course Names on, notifications say \u{201C}a course\u{201D} and \u{201C}An assignment\u{201D} instead of names. Grades are never shown in notifications.",
                bundle: #bundle,
                comment: "Settings, Reminders section footer: explains Hide Course Names. Appended after reminders.footer, separated by a blank line.")
        }

        public static func checking() -> LocalizedStringResource {
            LocalizedStringResource("reminders.status.checking", defaultValue: "Checking\u{2026}", bundle: #bundle,
                                    comment: "Settings, reminders row value, while the permission state is being read.")
        }

        public static func statusOff() -> LocalizedStringResource {
            LocalizedStringResource("reminders.status.off", defaultValue: "Off", bundle: #bundle,
                                    comment: "Settings, reminders row value: the permission has not been granted yet.")
        }

        public static func statusOn() -> LocalizedStringResource {
            LocalizedStringResource("reminders.status.on", defaultValue: "On", bundle: #bundle,
                                    comment: "Settings, reminders row value: the permission is granted.")
        }
    }

    /// Onboarding (`TallyFeatures/Onboarding`; ux-ui.md §3.2).
    public enum Onboarding {
        /// Shared by `FirstSyncSkeletonView`'s failure state and `SchoolSearchView`'s search-failed
        /// state: both retry the action that failed.
        public static func retry() -> LocalizedStringResource {
            LocalizedStringResource("onboarding.retry", defaultValue: "Retry", bundle: #bundle,
                                    comment: "Button that retries a failed action.")
        }

        /// Shared by the first-sync failure state and the sign-in hand-off screen: both end the
        /// current attempt and return to school search.
        public static func chooseDifferentSchool() -> LocalizedStringResource {
            LocalizedStringResource("onboarding.chooseDifferentSchool", defaultValue: "Choose a Different School", bundle: #bundle,
                                    comment: "Button that abandons the current sign-in or first-sync attempt and returns to school search.")
        }

        /// First sync (`Onboarding/FirstSync`; ux-ui.md §3.2 stage 5).
        public enum FirstSync {
            public static func announceCourses() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.announce.courses", defaultValue: "Found your courses", bundle: #bundle,
                                        comment: "VoiceOver announcement: the 'profile and courses' first-sync phase completed.")
            }

            public static func announceGrades() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.announce.grades", defaultValue: "Loaded grades", bundle: #bundle,
                                        comment: "VoiceOver announcement: the 'grades' first-sync phase completed.")
            }

            public static func announceDueDates() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.announce.dueDates", defaultValue: "Loaded your due dates", bundle: #bundle,
                                        comment: "VoiceOver announcement: the 'due items' first-sync phase completed.")
            }

            public static func announceCalendar() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.announce.calendar", defaultValue: "Loaded your calendar", bundle: #bundle,
                                        comment: "VoiceOver announcement: the 'calendar' first-sync phase completed.")
            }

            public static func slowLoadNotice() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.firstSync.slowLoadNotice", defaultValue: "Large course loads can take a minute — you can keep exploring", bundle: #bundle,
                    comment: "First sync: shown once the sync has taken longer than the slow-load threshold.")
            }

            /// Shared by the hero placeholder's title and the progress bar's accessibility label
            /// (identical text in both places today).
            public static func settingUpTally() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.settingUpTally", defaultValue: "Setting up Tally", bundle: #bundle,
                                        comment: "First sync hero placeholder title, and the progress bar's VoiceOver label.")
            }

            /// The progress bar's VoiceOver value. "Percent" does not change form in English for any count.
            public static func progressPercent(_ percent: Int) -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.progressPercent", defaultValue: "\(percent) percent", bundle: #bundle,
                                        comment: "First sync progress bar's VoiceOver value, 0-100.")
            }

            public static func failedTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.failedTitle", defaultValue: "Couldn't set up Tally", bundle: #bundle,
                                        comment: "First sync: title shown when the sync failed with nothing saved.")
            }

            public static func failureOffline() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.firstSync.failure.offline", defaultValue: "You're offline. Connect to the internet to load your courses.", bundle: #bundle,
                    comment: "First sync failure reason: offline.")
            }

            public static func failureAuthExpired() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.firstSync.failure.authExpired", defaultValue: "Your sign-in expired before setup finished. Sign in again to continue.", bundle: #bundle,
                    comment: "First sync failure reason: the sign-in expired mid-setup.")
            }

            public static func failureServerSlow() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.firstSync.failure.serverSlow", defaultValue: "Your school's Canvas is taking too long to respond. Try again in a moment.", bundle: #bundle,
                    comment: "First sync failure reason: rate-limited or server error.")
            }

            public static func failureUnknown() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.firstSync.failure.unknown", defaultValue: "Something went wrong setting up Tally. Try again.", bundle: #bundle,
                    comment: "First sync failure reason: an unrecognised or contract error.")
            }

            /// "Connecting to %@…" before the first phase completes. The placeholder is the school's
            /// display name (Canvas content, passed through untouched).
            public static func connectingTo(_ school: String) -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.connectingTo", defaultValue: "Connecting to \(school)…", bundle: #bundle,
                                        comment: "First sync status text before the first phase completes. The placeholder is the school's name.")
            }

            public static func almostDone() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.firstSync.almostDone", defaultValue: "Almost done", bundle: #bundle,
                                        comment: "First sync status text once every phase but the last has completed.")
            }

            /// "Setting up Tally · step N of 4".
            public static func stepProgress(_ step: Int, _ total: Int) -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.firstSync.stepProgress", defaultValue: "Setting up Tally · step \(step) of \(total)", bundle: #bundle,
                    comment: "First sync status text while phases are completing. Both placeholders are counts (current step, total steps).")
            }
        }

        /// School search (`Onboarding/SchoolSearch`; ux-ui.md §3.2.1).
        public enum SchoolSearch {
            public static func navigationTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.navigationTitle", defaultValue: "Find your school", bundle: #bundle,
                                        comment: "School search screen's navigation title.")
            }

            public static func searchPrompt() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.searchPrompt", defaultValue: "School name or Canvas address", bundle: #bundle,
                                        comment: "School search field's placeholder prompt.")
            }

            public static func cantFindIt() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.cantFindIt", defaultValue: "Can't find it?", bundle: #bundle,
                                        comment: "Toolbar button that opens help on finding the school's Canvas address.")
            }

            public static func noMatchHint() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.noMatchHint", defaultValue: "Try your Canvas web address instead, e.g. myschool.instructure.com.", bundle: #bundle,
                    comment: "School search: shown when no school matches the query.")
            }

            public static func offlineTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.offline.title", defaultValue: "You're offline", bundle: #bundle,
                                        comment: "School search: offline state title.")
            }

            public static func offlineDescription() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.offline.description", defaultValue: "Connect to the internet to find your school.", bundle: #bundle,
                    comment: "School search: offline state description.")
            }

            public static func searchFailedTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.searchFailed.title", defaultValue: "Couldn't search", bundle: #bundle,
                                        comment: "School search: the search request failed.")
            }

            public static func searchFailedDescription() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.searchFailed.description", defaultValue: "Something went wrong. Try again.", bundle: #bundle,
                    comment: "School search: the search request failed, description text.")
            }

            public static func recentSectionTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.recentSectionTitle", defaultValue: "Recent", bundle: #bundle,
                                        comment: "School search: section header above the most recently selected school.")
            }

            public static func typeAtLeast2Letters() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.typeAtLeast2Letters", defaultValue: "Type at least 2 letters of your school's name.", bundle: #bundle,
                    comment: "School search: idle-state hint.")
            }

            public static func searching() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.searching", defaultValue: "Searching\u{2026}", bundle: #bundle,
                                        comment: "School search: shown while a search is in flight.")
            }

            /// The visual "Use " prefix before the typed Canvas address (kept separate from the
            /// address itself, which is shown in italics and never translated).
            public static func useAddressPrefix() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.useAddressPrefix", defaultValue: "Use ", bundle: #bundle,
                                        comment: "School search: prefix before the typed Canvas address, e.g. 'Use ' + 'canvas.myschool.edu' in italics. Keep the trailing space.")
            }

            /// VoiceOver's combined form: "Use %@". The placeholder is the typed Canvas address.
            public static func useAddressAccessibilityLabel(_ host: String) -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.useAddressAccessibilityLabel", defaultValue: "Use \(host)", bundle: #bundle,
                                        comment: "School search: VoiceOver label for the typed-address row. The placeholder is the Canvas address.")
            }

            public static func addressHelpTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.addressHelp.title", defaultValue: "Finding your Canvas address", bundle: #bundle,
                                        comment: "Sheet title: help on finding the school's Canvas address.")
            }

            public static func addressHelpBody() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.addressHelp.body",
                    defaultValue: "Your Canvas address is the web address you already use to sign in on a computer — usually something like **canvas.yourschool.edu** or **yourschool.instructure.com**. You can find it in your school's Canvas mobile app under School Search, or by asking your instructor or IT help desk.",
                    bundle: #bundle,
                    comment: "Sheet body: help on finding the school's Canvas address. The ** markers are the source's own emphasis; whether Text renders them as Markdown bold here is UNVERIFIED (not changed by this sweep).")
            }

            /// X-1 (plan 08, owner-approved 2026-09-30): "It's a free app" became "It's an app" —
            /// Tally is a paid subscription. The placeholder is the school's display name.
            public static func adminRequestText(school: String, domain: String) -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.adminRequestText",
                    defaultValue: "Would you consider enabling Tally at \(school)? It's an app that shows students their Canvas courses, grades and due dates. There's no Tally server and no student accounts — Tally signs in directly with your Canvas, the same way a browser does. Setup takes a Canvas admin a few minutes: https://\(domain)/admin",
                    bundle: #bundle,
                    comment: "X-1: share text sent to a school admin, asking them to enable Tally. The first placeholder is the school's name; the second is Tally's admin-setup domain.")
            }

            public static func notEnabledTitle(school: String) -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.notEnabled.title", defaultValue: "Tally isn't available at \(school) yet", bundle: #bundle,
                                        comment: "Shown when a found school has no Canvas client registration yet. The placeholder is the school's name.")
            }

            public static func notEnabledDescription() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.schoolSearch.notEnabled.description", defaultValue: "Your school's Canvas admin needs to approve Tally.", bundle: #bundle,
                    comment: "Shown when a found school has no Canvas client registration yet.")
            }

            public static func askMySchool() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.askMySchool", defaultValue: "Ask My School", bundle: #bundle,
                                        comment: "Share-sheet button that sends the admin request text (X-1).")
            }

            public static func notAvailableYetNavTitle() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.schoolSearch.notAvailableYet.navigationTitle", defaultValue: "Not available yet", bundle: #bundle,
                                        comment: "Navigation title of the 'school found but not enabled' screen.")
            }
        }

        /// Sign-in hand-off (`Onboarding/SignIn`; ux-ui.md §3.2 stage 4).
        public enum SignIn {
            public static func signInTo(_ school: String) -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.title", defaultValue: "Sign in to \(school)", bundle: #bundle,
                                        comment: "Sign-in hand-off screen title. The placeholder is the school's name.")
            }

            public static func cancelledNotice() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.cancelledNotice", defaultValue: "Sign-in cancelled. Nothing was shared.", bundle: #bundle,
                                        comment: "Sign-in hand-off: the student cancelled the system sign-in sheet.")
            }

            public static func accessDenied() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.accessDenied", defaultValue: "Tally needs read access to show your courses. You can try again any time.", bundle: #bundle,
                    comment: "Sign-in hand-off: the student declined read access.")
            }

            /// The placeholder is the school's name.
            public static func networkFailure(_ school: String) -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.networkFailure", defaultValue: "Couldn't reach \(school). Check your connection and try again.", bundle: #bundle,
                    comment: "Sign-in hand-off: a network failure reaching the school's Canvas. The placeholder is the school's name.")
            }

            public static func otherFailure() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.otherFailure", defaultValue: "Something went wrong signing in. You can try again.", bundle: #bundle,
                    comment: "Sign-in hand-off: an unrecognised sign-in failure.")
            }

            public static func expectation1Title() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.expectation1.title", defaultValue: "Use your usual school login", bundle: #bundle,
                                        comment: "Sign-in hand-off, first expectation row title.")
            }

            public static func expectation1Detail() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.expectation1.detail", defaultValue: "You sign in on your school's page. Tally never sees your password.", bundle: #bundle,
                    comment: "Sign-in hand-off, first expectation row detail.")
            }

            public static func expectation2Title() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.expectation2.title", defaultValue: "iOS will ask first", bundle: #bundle,
                                        comment: "Sign-in hand-off, second expectation row title.")
            }

            /// The placeholder is the Canvas host (data, never translated).
            public static func expectation2Detail(_ host: String) -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.expectation2.detail",
                    defaultValue: "You'll see \u{201c}Tally Wants to Use \(host) to Sign In\u{201d}. Choose Continue.",
                    bundle: #bundle,
                    comment: "Sign-in hand-off, second expectation row detail. The placeholder is the Canvas host shown in iOS's own sheet; 'Tally Wants to Use … to Sign In' and 'Continue' are iOS's own wording, quoted.")
            }

            public static func expectation3Title() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.expectation3.title", defaultValue: "Approve read access", bundle: #bundle,
                                        comment: "Sign-in hand-off, third expectation row title.")
            }

            public static func expectation3Detail() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.expectation3.detail", defaultValue: "Canvas asks you to authorize Tally. Tally only reads your courses, grades and due dates.", bundle: #bundle,
                    comment: "Sign-in hand-off, third expectation row detail.")
            }

            public static func expectation4Title() -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.expectation4.title", defaultValue: "Then you're back here", bundle: #bundle,
                                        comment: "Sign-in hand-off, fourth expectation row title.")
            }

            public static func expectation4Detail() -> LocalizedStringResource {
                LocalizedStringResource(
                    "onboarding.signIn.expectation4.detail", defaultValue: "Tally loads your courses straight away.", bundle: #bundle,
                    comment: "Sign-in hand-off, fourth expectation row detail.")
            }

            /// The placeholder is the school's name.
            public static func continueTo(_ school: String) -> LocalizedStringResource {
                LocalizedStringResource("onboarding.signIn.continueTo", defaultValue: "Continue to \(school)", bundle: #bundle,
                                        comment: "Sign-in hand-off: the primary action button. The placeholder is the school's name.")
            }
        }
    }

    /// The Calendar tab (`TallyFeatures/Calendar`; ux-ui.md §3.7.4, UX-WP-17).
    public enum Calendar {
        /// The agenda row's time text and its spoken (VoiceOver) form for an all-day item.
        public static func allDay() -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.allDay", defaultValue: "All day", bundle: #bundle,
                                    comment: "Calendar agenda row: the time text for an all-day class or event.")
        }

        public static func allDaySpoken() -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.allDay.spoken", defaultValue: "all day", bundle: #bundle,
                                    comment: "Calendar agenda row: VoiceOver's spoken form for an all-day class or event, inside a longer accessibility label.")
        }

        /// "Due 11:59 PM". The placeholder is already a formatted, locale-aware time.
        public static func due(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.due", defaultValue: "Due \(time)", bundle: #bundle,
                                    comment: "Calendar agenda row: the time text for an assignment due at this time. The placeholder is the already-formatted time.")
        }

        public static func dueSpoken(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.due.spoken", defaultValue: "due at \(time)", bundle: #bundle,
                                    comment: "Calendar agenda row: VoiceOver's spoken form for an assignment's due time, inside a longer accessibility label. The placeholder is the already-formatted time.")
        }

        /// "9:00 AM – 9:50 AM". Both placeholders are already formatted, locale-aware times.
        public static func timeRange(_ start: String, _ end: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.timeRange", defaultValue: "\(start) – \(end)", bundle: #bundle,
                                    comment: "Calendar agenda row: a class or event's time range. Both placeholders are already-formatted times.")
        }

        public static func timeRangeSpoken(_ start: String, _ end: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.timeRange.spoken", defaultValue: "\(start) to \(end)", bundle: #bundle,
                                    comment: "Calendar agenda row: VoiceOver's spoken form of a class or event's time range, inside a longer accessibility label. Both placeholders are already-formatted times.")
        }

        /// The conflict line when a row overlaps exactly one other item.
        public static func overlapsWith(_ other: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.overlapsWith", defaultValue: "Overlaps with \(other)", bundle: #bundle,
                                    comment: "Calendar agenda row: this item overlaps one other item. The placeholder is the other item's title (and course code, if any).")
        }

        /// The conflict line when a row overlaps more than one other item.
        public static func overlapsWithMore(_ other: String, _ moreCount: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "calendar.agenda.overlapsWithMore", defaultValue: "Overlaps with \(other) and \(moreCount) more", bundle: #bundle,
                comment: "Calendar agenda row: this item overlaps more than one other item. The first placeholder is the first other item's title; the second is how many more. 'more' does not change form in English for this count.")
        }

        /// Inside the row's combined accessibility label, before the conflict text.
        public static func conflictSpoken(_ conflictText: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.conflict.spoken", defaultValue: "conflict: \(conflictText)", bundle: #bundle,
                                    comment: "Calendar agenda row: prefixes the conflict line inside the row's combined VoiceOver accessibility label.")
        }

        /// Inside the row's combined accessibility label, when the item is an exam.
        public static func examSpoken() -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.exam.spoken", defaultValue: "exam", bundle: #bundle,
                                    comment: "Calendar agenda row: appended to the row's combined VoiceOver accessibility label when the item is an exam.")
        }

        /// The week strip's spoken label: how many items a day has. A plural key: the catalog holds
        /// one form per plural category (never a hand-built "s").
        public static func itemCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.itemCount", defaultValue: "\(count) items", bundle: #bundle,
                                    comment: "Week strip, VoiceOver: how many agenda items a day has. A plural key.")
        }

        /// The week strip's spoken label, when the day is today.
        public static func todaySpoken() -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.today.spoken", defaultValue: "today", bundle: #bundle,
                                    comment: "Week strip, VoiceOver: appended to a day's spoken label when that day is today.")
        }

        /// The agenda's section heading for today: "Today · Mon, Sep 28". The placeholder is the
        /// already-formatted day heading.
        public static func headingToday(_ heading: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.agenda.heading.today", defaultValue: "Today · \(heading)", bundle: #bundle,
                                    comment: "Calendar agenda section heading for today's section, with the already-formatted day heading after it.")
        }

        /// A day's agenda section with nothing in it.
        public static func nothingScheduled() -> LocalizedStringResource {
            LocalizedStringResource("calendar.nothingScheduled", defaultValue: "Nothing scheduled", bundle: #bundle,
                                    comment: "Calendar agenda: shown in a day's section when it has no classes, events or due items.")
        }

        /// The Calendar tab's own name: the navigation title fallback (before any month is known)
        /// and the Settings section header for the same feature.
        public static func tabTitle() -> LocalizedStringResource {
            LocalizedStringResource("calendar.tabTitle", defaultValue: "Calendar", bundle: #bundle,
                                    comment: "The Calendar tab's own name: used as its navigation title (before a month is known) and as the Settings section header for the Canvas calendar subscription.")
        }

        /// The toolbar menu's accessibility label (VoiceOver).
        public static func optionsMenuLabel() -> LocalizedStringResource {
            LocalizedStringResource("calendar.optionsMenu.label", defaultValue: "Calendar options", bundle: #bundle,
                                    comment: "VoiceOver label for the Calendar tab's toolbar options menu.")
        }

        /// The menu item that subscribes to the student's own Canvas calendar feed (PMO R6).
        public static func subscribeMenuItem() -> LocalizedStringResource {
            LocalizedStringResource("calendar.optionsMenu.subscribe", defaultValue: "Subscribe to Canvas Calendar…", bundle: #bundle,
                                    comment: "Calendar tab's options menu item that subscribes Calendar.app to the student's own Canvas calendar feed.")
        }

        /// The Agenda/Day view-mode picker's own label (not shown; read by VoiceOver).
        public static func viewPickerLabel() -> LocalizedStringResource {
            LocalizedStringResource("calendar.optionsMenu.viewPicker", defaultValue: "View", bundle: #bundle,
                                    comment: "VoiceOver label for the picker that switches the Calendar tab between Agenda and Day (timeline) views.")
        }

        public static func modeAgenda() -> LocalizedStringResource {
            LocalizedStringResource("calendar.mode.agenda", defaultValue: "Agenda", bundle: #bundle,
                                    comment: "Calendar view-mode picker option: the agenda list.")
        }

        public static func modeDay() -> LocalizedStringResource {
            LocalizedStringResource("calendar.mode.day", defaultValue: "Day", bundle: #bundle,
                                    comment: "Calendar view-mode picker option: the single-day hour timeline.")
        }

        /// The chip on an agenda row that is an exam.
        public static func examChip() -> LocalizedStringResource {
            LocalizedStringResource("calendar.exam.chip", defaultValue: "Exam", bundle: #bundle,
                                    comment: "Status chip on a Calendar agenda row that insights-at-a-glance detected as an exam.")
        }

        /// "Add to Calendar" button's accessibility label. The placeholder is the item's title.
        public static func addToCalendar(_ title: String) -> LocalizedStringResource {
            LocalizedStringResource("calendar.addToCalendar.label", defaultValue: "Add \(title) to Calendar", bundle: #bundle,
                                    comment: "VoiceOver label for the button that opens the system event editor pre-filled with this agenda item. The placeholder is the item's title.")
        }

        /// Shared by the Calendar tab's menu and the Settings calendar row: the alert shown when
        /// subscribing is tried on sample data, which has no real Canvas feed.
        public static func subscribeAlertTitle() -> LocalizedStringResource {
            LocalizedStringResource("calendar.subscribeAlert.title", defaultValue: "Subscribing needs your school's Canvas", bundle: #bundle,
                                    comment: "Alert title shown when 'Subscribe to Canvas Calendar' is tried on sample data, which has no real Canvas feed. Shown from the Calendar tab and from Settings.")
        }

        public static func subscribeAlertOK() -> LocalizedStringResource {
            LocalizedStringResource("calendar.subscribeAlert.ok", defaultValue: "OK", bundle: #bundle,
                                    comment: "Dismiss button on the sample-data calendar subscription alert. Shown from the Calendar tab and from Settings.")
        }

        /// The Calendar tab's own wording for that alert's body (longer than Settings' own wording;
        /// the two are kept as separate keys rather than merged, to keep each screen's English
        /// byte-identical to before the sweep).
        public static func subscribeSampleNote() -> LocalizedStringResource {
            LocalizedStringResource(
                "calendar.subscribeAlert.body",
                defaultValue: "Sample data has no real calendar feed. Once you sign in, this adds your own Canvas calendar to the Calendar app, and it stays up to date there.",
                bundle: #bundle,
                comment: "Calendar tab's sample-data subscription alert body.")
        }
    }

    /// The first-run welcome screen (`WelcomeView`; ux-ui.md §3.2).
    public enum Welcome {
        /// The tagline under the wordmark.
        public static func tagline() -> LocalizedStringResource {
            LocalizedStringResource(
                "welcome.tagline", defaultValue: "Every class, grade and deadline from Canvas — at a glance", bundle: #bundle,
                comment: "Welcome screen tagline, under the Tally wordmark.")
        }

        public static func benefitStanding() -> LocalizedStringResource {
            LocalizedStringResource("welcome.benefit.standing", defaultValue: "See where you stand", bundle: #bundle,
                                    comment: "Welcome screen benefit row.")
        }

        public static func benefitDeadlines() -> LocalizedStringResource {
            LocalizedStringResource("welcome.benefit.deadlines", defaultValue: "Stay ahead of deadlines", bundle: #bundle,
                                    comment: "Welcome screen benefit row.")
        }

        public static func benefitPrivate() -> LocalizedStringResource {
            LocalizedStringResource("welcome.benefit.private", defaultValue: "Private by design", bundle: #bundle,
                                    comment: "Welcome screen benefit row title.")
        }

        public static func benefitPrivateDetail() -> LocalizedStringResource {
            LocalizedStringResource(
                "welcome.benefit.private.detail", defaultValue: "No Tally account. Your data stays on this iPhone.", bundle: #bundle,
                comment: "Welcome screen benefit row detail, under 'Private by design'.")
        }
    }

    /// The "last refreshed" footer, breadcrumb and subtitle (UX-WP-06, `FreshnessPresenter`,
    /// `TallyFeatures/{Shell,Home}`), the kit-11 copy of ux-ui.md §3.3's table.
    public enum Freshness {
        public static func notRefreshedYet() -> LocalizedStringResource {
            LocalizedStringResource("freshness.notRefreshedYet", defaultValue: "Not refreshed yet", bundle: #bundle,
                                    comment: "Freshness footer before the first successful sync.")
        }

        public static func updatedJustNow() -> LocalizedStringResource {
            LocalizedStringResource("freshness.updatedJustNow", defaultValue: "Updated just now", bundle: #bundle,
                                    comment: "Freshness footer: the data refreshed less than a minute ago.")
        }

        /// The placeholder is an already-formatted, locale-aware time or date (`FreshnessPresenter.when`).
        public static func updated(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("freshness.updated", defaultValue: "Updated \(time)", bundle: #bundle,
                                    comment: "Freshness footer: when the data last refreshed. The placeholder is an already-formatted time or date.")
        }

        /// The fallback base text in `.refreshing` when there is no saved data yet to show a time for.
        public static func refreshingFallback() -> LocalizedStringResource {
            LocalizedStringResource("freshness.refreshing.fallback", defaultValue: "Refreshing", bundle: #bundle,
                                    comment: "Freshness footer base text while refreshing, before any data has been saved.")
        }

        /// Appends the spinner suffix to the base text (either 'Updated …' or 'Refreshing').
        public static func refreshingSuffix(_ base: String) -> LocalizedStringResource {
            LocalizedStringResource("freshness.refreshing.suffix", defaultValue: "\(base) · Refreshing…", bundle: #bundle,
                                    comment: "Freshness footer while a refresh is in progress. The placeholder is the base text ('Updated …' or 'Refreshing').")
        }

        public static func firstSyncSlow() -> LocalizedStringResource {
            LocalizedStringResource(
                "freshness.firstSyncSlow", defaultValue: "First sync is taking longer than expected", bundle: #bundle,
                comment: "Freshness footer: the very first sync is slow and there is no cache yet.")
        }

        /// The short "Saved …" text shown with the stale breadcrumb. The placeholder is an
        /// already-formatted time or date.
        public static func saved(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("freshness.saved", defaultValue: "Saved \(time)", bundle: #bundle,
                                    comment: "Freshness footer short text once there is saved data to show, paired with a stale breadcrumb. The placeholder is an already-formatted time or date.")
        }

        public static func delayedLong(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "freshness.delayed.long",
                defaultValue: "Live refresh is taking longer than expected — showing saved data from \(time).",
                bundle: #bundle,
                comment: "Stale breadcrumb: a live refresh is slow, so Tally is showing saved data. The placeholder is an already-formatted time or date.")
        }

        public static func offlineNoData() -> LocalizedStringResource {
            LocalizedStringResource("freshness.offline.noData", defaultValue: "No saved data — you're offline", bundle: #bundle,
                                    comment: "Freshness footer: offline, with nothing saved yet to show.")
        }

        public static func offlineLong() -> LocalizedStringResource {
            LocalizedStringResource(
                "freshness.offline.long", defaultValue: "You're offline — showing your latest saved data.", bundle: #bundle,
                comment: "Stale breadcrumb: offline, showing the latest saved data.")
        }

        public static func signInExpired() -> LocalizedStringResource {
            LocalizedStringResource("freshness.signInExpired", defaultValue: "Sign-in expired", bundle: #bundle,
                                    comment: "Freshness footer: the sign-in expired, with nothing saved yet to show.")
        }

        public static func authExpiredLong(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "freshness.authExpired.long", defaultValue: "Your sign-in expired — showing saved data from \(time).", bundle: #bundle,
                comment: "Stale breadcrumb: the sign-in expired, showing saved data. The placeholder is an already-formatted time or date.")
        }

        public static func couldntRefreshYet() -> LocalizedStringResource {
            LocalizedStringResource("freshness.couldntRefreshYet", defaultValue: "Couldn't refresh yet", bundle: #bundle,
                                    comment: "Freshness footer: a refresh failed, with nothing saved yet to show.")
        }

        public static func failedLong(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "freshness.failed.long", defaultValue: "Couldn't refresh — showing saved data from \(time).", bundle: #bundle,
                comment: "Stale breadcrumb: a refresh failed, showing saved data. The placeholder is an already-formatted time or date.")
        }

        /// The refresh button's accessibility label (an icon-only button).
        public static func refreshButtonLabel() -> LocalizedStringResource {
            LocalizedStringResource("freshness.refreshButton.label", defaultValue: "Refresh", bundle: #bundle,
                                    comment: "VoiceOver label for the freshness footer's icon-only refresh button.")
        }
    }

    /// Settings (`TallyFeatures/Settings`; ux-ui.md §3.7.7).
    public enum Settings {
        public static func navigationTitle() -> LocalizedStringResource {
            LocalizedStringResource("settings.navigationTitle", defaultValue: "Settings", bundle: #bundle,
                                    comment: "Settings sheet's navigation title.")
        }

        /// The sign-out confirmation dialog's "Cancel" action.
        public static func cancel() -> LocalizedStringResource {
            LocalizedStringResource("settings.cancel", defaultValue: "Cancel", bundle: #bundle,
                                    comment: "Settings: cancels the sign-out confirmation dialog.")
        }

        /// Settings' own (shorter) wording for the sample-data calendar subscription alert; the
        /// Calendar tab's own wording (`calendar.subscribeAlert.body`) is one sentence longer. Kept
        /// as separate keys so each screen's English stays byte-identical to before the sweep.
        public static func calendarSampleNote() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.calendar.sampleNote",
                defaultValue: "Sample data has no real calendar feed. Once you sign in, this adds your own Canvas calendar to the Calendar app.",
                bundle: #bundle,
                comment: "Settings: sample-data calendar subscription alert body.")
        }

        public static func signOutTitle() -> LocalizedStringResource {
            LocalizedStringResource("settings.signOut.title", defaultValue: "Sign out and erase?", bundle: #bundle,
                                    comment: "Settings: the sign-out confirmation dialog's title.")
        }

        public static func signOutConfirmation() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.signOut.confirmation",
                defaultValue: "Tally will delete your saved courses and grades from this iPhone. Canvas in Safari may stay signed in.",
                bundle: #bundle,
                comment: "Settings: the sign-out confirmation dialog's message (ux-ui.md §3.7.7, SEC §3, ASC R9).")
        }

        public static func thresholdFooter() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.threshold.footer",
                defaultValue: "A course's grade shows in \u{201C}What changed\u{201D} only when it moves at least this much. Assignment grades always show.",
                bundle: #bundle,
                comment: "Settings: footer under the 'What changed' threshold controls. The curly quotes match the Dashboard's own 'What changed' wording.")
        }

        public static func widgetGradesTitle() -> LocalizedStringResource {
            LocalizedStringResource("settings.widgetGrades.title", defaultValue: "Show Grades in Widgets", bundle: #bundle,
                                    comment: "Settings toggle: shows the average grade band in the Standing widget (M2-C2 OI5, opt-in, PMO R10).")
        }

        public static func widgetGradesFooter() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.widgetGrades.footer",
                defaultValue: "The Standing widget shows your average grade band. It is hidden while your iPhone is locked. A change reaches the widget right away.",
                bundle: #bundle,
                comment: "Settings: footer under 'Show Grades in Widgets'.")
        }

        public static func sampleModeLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.sampleMode.label", defaultValue: "Mode", bundle: #bundle,
                                    comment: "Settings row title, sample mode: labels the 'Sample data' value.")
        }

        public static func sampleModeValue() -> LocalizedStringResource {
            LocalizedStringResource("settings.sampleMode.value", defaultValue: "Sample data", bundle: #bundle,
                                    comment: "Settings row value, sample mode.")
        }

        public static func sampleModeCaption() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.sampleMode.caption",
                defaultValue: "Everything here is fictional sample data. Nothing is saved on this iPhone.",
                bundle: #bundle,
                comment: "Settings, sample mode: explains that nothing on screen is real or saved.")
        }

        public static func exitSampleData() -> LocalizedStringResource {
            LocalizedStringResource("settings.exitSampleData", defaultValue: "Exit Sample Data", bundle: #bundle,
                                    comment: "Settings button, sample mode: leaves sample mode (shown instead of Sign Out & Erase, which sample mode has nothing to do).")
        }

        public static func schoolLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.school.label", defaultValue: "School", bundle: #bundle,
                                    comment: "Settings row title: the signed-in student's school host.")
        }

        public static func signedInAsLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.signedInAs.label", defaultValue: "Signed in as", bundle: #bundle,
                                    comment: "Settings row title: the signed-in student's display name.")
        }

        public static func accountHeader() -> LocalizedStringResource {
            LocalizedStringResource("settings.account.header", defaultValue: "Account", bundle: #bundle,
                                    comment: "Settings section header: the account section.")
        }

        public static func showEveryGradeChange() -> LocalizedStringResource {
            LocalizedStringResource("settings.showEveryGradeChange", defaultValue: "Show every grade change", bundle: #bundle,
                                    comment: "Settings toggle: the 'What changed' threshold shows every grade change, however small (DG-1).")
        }

        /// "At least %@", where the placeholder is an already-formatted points amount
        /// (`ThresholdText.points`, e.g. '1 point' or '2.5 points').
        public static func atLeastPoints(_ points: String) -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.atLeast", defaultValue: "At least \(points)", bundle: #bundle,
                                    comment: "Settings: the 'What changed' threshold shown as a minimum points amount. The placeholder is an already-formatted points amount, such as '1 point' or '2.5 points'.")
        }

        public static func perCourseLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.perCourse.label", defaultValue: "Per course", bundle: #bundle,
                                    comment: "Settings row title: opens the per-course 'What changed' threshold overrides.")
        }

        public static func settingSaveFailed() -> LocalizedStringResource {
            LocalizedStringResource("settings.saveFailed", defaultValue: "This setting couldn't be saved.", bundle: #bundle,
                                    comment: "Settings: shown under a toggle or control whose last change failed to save.")
        }

        public static func whatChangedHeader() -> LocalizedStringResource {
            LocalizedStringResource("settings.whatChanged.header", defaultValue: "What changed", bundle: #bundle,
                                    comment: "Settings section header: the 'What changed' (digest/change-alert threshold) section.")
        }

        public static func lastRefreshedLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.lastRefreshed.label", defaultValue: "Last refreshed", bundle: #bundle,
                                    comment: "Settings row title: when Tally last refreshed from Canvas.")
        }

        public static func refreshNow() -> LocalizedStringResource {
            LocalizedStringResource("settings.refreshNow", defaultValue: "Refresh Now", bundle: #bundle,
                                    comment: "Settings button: requests an immediate refresh.")
        }

        public static func backgroundAppRefreshLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.backgroundAppRefresh.label", defaultValue: "Background App Refresh", bundle: #bundle,
                                    comment: "Settings row title: the iOS Background App Refresh permission's state.")
        }

        public static func notUsedForSampleData() -> LocalizedStringResource {
            LocalizedStringResource("settings.notUsedForSampleData", defaultValue: "Not used for sample data", bundle: #bundle,
                                    comment: "Settings row value: Background App Refresh does nothing in sample mode.")
        }

        public static func dataAndRefreshHeader() -> LocalizedStringResource {
            LocalizedStringResource("settings.dataAndRefresh.header", defaultValue: "Data & Refresh", bundle: #bundle,
                                    comment: "Settings section header: data and refresh.")
        }

        /// The Settings row's own subscribe button (no ellipsis; distinct from the Calendar tab's
        /// menu item `calendar.optionsMenu.subscribe`, which has one).
        public static func subscribeButton() -> LocalizedStringResource {
            LocalizedStringResource("settings.subscribeButton", defaultValue: "Subscribe to Canvas Calendar", bundle: #bundle,
                                    comment: "Settings button that subscribes Calendar.app to the student's own Canvas calendar feed.")
        }

        public static func calendarFooter() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.calendar.footer",
                defaultValue: "Adds your own Canvas calendar to the Calendar app, where it stays up to date. To add one item, use Add to Calendar on it. Tally never asks for access to your calendars.",
                bundle: #bundle,
                comment: "Settings: footer under the Canvas calendar subscription button.")
        }

        /// Shared by the Settings row that opens "What Tally Stores" and that screen's own
        /// navigation title.
        public static func whatTallyStoresLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.whatTallyStores.label", defaultValue: "What Tally Stores", bundle: #bundle,
                                    comment: "Settings row title and screen title: what Tally stores and where.")
        }

        public static func privacySecurityHeader() -> LocalizedStringResource {
            LocalizedStringResource("settings.privacySecurity.header", defaultValue: "Privacy & Security", bundle: #bundle,
                                    comment: "Settings section header: privacy and security (app lock).")
        }

        public static func versionLabel() -> LocalizedStringResource {
            LocalizedStringResource("settings.version.label", defaultValue: "Version", bundle: #bundle,
                                    comment: "Settings row title: the app's version and build number.")
        }

        public static func aboutHeader() -> LocalizedStringResource {
            LocalizedStringResource("settings.about.header", defaultValue: "About", bundle: #bundle,
                                    comment: "Settings section header: version and the non-affiliation disclaimer.")
        }

        public static func requireUnlock() -> LocalizedStringResource {
            LocalizedStringResource("settings.appLock.requireUnlock", defaultValue: "Require Unlock", bundle: #bundle,
                                    comment: "Settings: the App Lock grace-period picker's own label (how long Tally may stay in the background before it locks again).")
        }

        /// "Default (%@)". The placeholder is the global threshold's already-localized description
        /// (`ThresholdText.describe`, e.g. 'every change' or 'at least 1 point').
        public static func defaultThreshold(_ description: String) -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.default", defaultValue: "Default (\(description))", bundle: #bundle,
                                    comment: "Per-course 'What changed' threshold menu: the option that follows the global default. The placeholder is the global default's own description, such as 'every change' or 'at least 1 point'.")
        }

        /// The per-course threshold menu's "every change" option (capitalized: it stands alone as a
        /// menu item, unlike `settings.threshold.describe.everyChange`, used mid-sentence).
        public static func everyChangeOption() -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.everyChangeOption", defaultValue: "Every change", bundle: #bundle,
                                    comment: "Per-course 'What changed' threshold menu option: every grade change, however small.")
        }

        public static func perCourseNavTitle() -> LocalizedStringResource {
            LocalizedStringResource("settings.perCourse.navigationTitle", defaultValue: "Per Course", bundle: #bundle,
                                    comment: "Navigation title of the per-course 'What changed' threshold screen.")
        }

        public static func storesNoAccount() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.stores.noAccount",
                defaultValue: "There is no Tally account and no Tally server. Tally talks only to your school's Canvas.",
                bundle: #bundle,
                comment: "'What Tally Stores' screen, first line.")
        }

        public static func storesCanvasData() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.stores.canvasData",
                defaultValue: "After you sign in, Tally keeps your latest Canvas courses, grades, assignments and calendar on this iPhone, sealed with a key that stays on this iPhone. Each refresh replaces the copy before it.",
                bundle: #bundle,
                comment: "'What Tally Stores' screen: what is kept on the iPhone and how.")
        }

        public static func storesKeychain() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.stores.keychain", defaultValue: "Your Canvas sign-in is kept in the iPhone's Keychain.", bundle: #bundle,
                comment: "'What Tally Stores' screen: where the Canvas credential lives.")
        }

        public static func storesLocalOnly() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.stores.localOnly",
                defaultValue: "Your settings, course order and To-Do marks stay on this iPhone and are not included in backups.",
                bundle: #bundle,
                comment: "'What Tally Stores' screen: local-only settings and state.")
        }

        public static func storesSampleNeverSaved() -> LocalizedStringResource {
            LocalizedStringResource("settings.stores.sampleNeverSaved", defaultValue: "Sample data is never saved.", bundle: #bundle,
                                    comment: "'What Tally Stores' screen: sample mode persists nothing.")
        }

        public static func storesSignOutErase() -> LocalizedStringResource {
            LocalizedStringResource(
                "settings.stores.signOutErase", defaultValue: "Sign Out & Erase deletes all of it from this iPhone.", bundle: #bundle,
                comment: "'What Tally Stores' screen, last line: what Sign Out & Erase does.")
        }

        /// `ThresholdText.points`'s exact singular case (the raw `Double` value equals 1). Kept as a
        /// separate key from `settings.threshold.pointsOther` rather than a catalog plural variant:
        /// the selector is a `Double` equality check against the *unrounded* value, not a count, and
        /// L10N-02 found multi-argument catalog plural substitutions untested in this repo
        /// (`l10n-infra-report.md` §7). `SettingsModel.pointStep` constrains every reachable value to
        /// exact 0.5 steps, so this is the only value that ever displays as "1".
        public static func pointsOne() -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.pointsOne", defaultValue: "1 point", bundle: #bundle,
                                    comment: "A 'What changed' points threshold of exactly 1 point.")
        }

        /// The placeholder is the already-formatted points amount (0 or 1 fraction digits).
        public static func pointsOther(_ number: String) -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.pointsOther", defaultValue: "\(number) points", bundle: #bundle,
                                    comment: "A 'What changed' points threshold other than exactly 1 point. The placeholder is the already-formatted amount, such as '0.5' or '2.5'.")
        }

        /// `ThresholdText.describe`'s mid-sentence form of `pointsOne`/`pointsOther` (lower case,
        /// used after 'Default (' and inside `settings.threshold.atLeast`).
        public static func describeEveryChange() -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.describe.everyChange", defaultValue: "every change", bundle: #bundle,
                                    comment: "Lower-case, mid-sentence form of the 'every change' threshold (inside 'Default (…)').")
        }

        public static func describeAtLeast(_ points: String) -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.describe.atLeast", defaultValue: "at least \(points)", bundle: #bundle,
                                    comment: "Lower-case, mid-sentence form of a points threshold (inside 'Default (…)'). The placeholder is an already-formatted points amount.")
        }

        public static func overridesNone() -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.overridesNone", defaultValue: "None", bundle: #bundle,
                                    comment: "Settings 'Per course' row value: no course has its own 'What changed' threshold override.")
        }

        /// A plural key: how many courses have their own threshold override.
        public static func overridesCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("settings.threshold.overridesCount", defaultValue: "\(count) courses", bundle: #bundle,
                                    comment: "Settings 'Per course' row value: how many courses have their own 'What changed' threshold override. A plural key.")
        }

        public static func backgroundRefreshUnknown() -> LocalizedStringResource {
            LocalizedStringResource("settings.backgroundRefresh.unknown", defaultValue: "Unknown", bundle: #bundle,
                                    comment: "Background App Refresh row value: the permission's state could not be read.")
        }

        public static func backgroundRefreshOn() -> LocalizedStringResource {
            LocalizedStringResource("settings.backgroundRefresh.on", defaultValue: "On", bundle: #bundle,
                                    comment: "Background App Refresh row value: the permission is granted.")
        }

        public static func backgroundRefreshOff() -> LocalizedStringResource {
            LocalizedStringResource("settings.backgroundRefresh.off", defaultValue: "Off", bundle: #bundle,
                                    comment: "Background App Refresh row value: the student turned the permission off.")
        }

        public static func backgroundRefreshRestricted() -> LocalizedStringResource {
            LocalizedStringResource("settings.backgroundRefresh.restricted", defaultValue: "Restricted", bundle: #bundle,
                                    comment: "Background App Refresh row value: restricted (for example by Screen Time).")
        }
    }
}
