import Foundation

/// Plan 08 XG-04 and XG-06: the student's controls for a course whose grades may be kept outside
/// Canvas. Kept in their own file, beside `L10n.swift`, so this stream's additions never touch the
/// lines another stream adds there; the keys are in the same catalog.
extension L10n {
    /// XG-04 (owner decision G-3): Course Detail's menu, "This course's grades are kept outside
    /// Canvas: Automatic / Yes / No".
    public enum GradeOverride {
        /// The toolbar menu's label (VoiceOver, Voice Control).
        public static func menu() -> LocalizedStringResource {
            LocalizedStringResource("courseDetail.override.menu", defaultValue: "Course Options", bundle: #bundle,
                                    comment: "Label of the Course Detail toolbar menu (an ellipsis button) that holds the course's settings.")
        }

        /// The question the three answers belong to (plan 08 G-3's wording).
        public static func title() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.override.title", defaultValue: "This course's grades are kept outside Canvas", bundle: #bundle,
                comment: "Course Detail menu: a setting whose answers are Automatic, Yes and No. Yes means the student's school keeps this course's grades in another system (for example a district grade portal), not in Canvas.")
        }

        /// ux-fp1 D17 (pending owner approval): the Course Options menu's submenu row, shortened
        /// from `title()`'s full question because iOS menu rows truncate single-line labels
        /// instead of wrapping them, and the full sentence clipped on the smallest iPhone.
        public static func menuRowTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.override.menuRowTitle", defaultValue: "Grades kept outside Canvas", bundle: #bundle,
                comment: "Course Options menu row label for the grades-outside-Canvas setting (Automatic/Yes/No) — the same question as courseDetail.override.title, shortened because this iOS menu row truncates rather than wraps.")
        }

        public static func automatic() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.override.automatic", defaultValue: "Automatic", bundle: #bundle,
                comment: "Answer to 'This course's grades are kept outside Canvas': Tally decides from what Canvas shows.")
        }

        public static func yes() -> LocalizedStringResource {
            LocalizedStringResource("courseDetail.override.yes", defaultValue: "Yes", bundle: #bundle,
                                    comment: "Answer to 'This course's grades are kept outside Canvas': yes, they are.")
        }

        public static func no() -> LocalizedStringResource {
            LocalizedStringResource("courseDetail.override.no", defaultValue: "No", bundle: #bundle,
                                    comment: "Answer to 'This course's grades are kept outside Canvas': no, they are in Canvas.")
        }
    }

    /// XG-06 (owner decision, 2026-10-01): the what-if for a course whose grades are kept outside
    /// Canvas: the approved disclaimer, and the categories' weights the student may set.
    public enum WhatIfEstimate {
        /// Approved verbatim by the owner (plan 08 §2, 2026-10-01).
        public static func disclaimer() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.disclaimer",
                defaultValue: "Estimate only. Your school keeps grades outside Canvas, so Tally uses this course's Canvas categories, which may not match how your school weighs your grade.",
                bundle: #bundle,
                comment: "At the top of the what-if calculator for a course whose grades the school keeps in another system: the student types their real scores and Tally estimates the course grade.")
        }

        public static func weightsHeader() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.weightsHeader", defaultValue: "Category weights", bundle: #bundle,
                comment: "Section header in the what-if calculator: how much each assignment category counts toward the course grade.")
        }

        public static func weightsFooter() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.weightsFooter",
                defaultValue: "Each weight is a percent of the grade. Categories you leave blank use this course's setting in Canvas.",
                bundle: #bundle, comment: "Under the category weights in the what-if calculator.")
        }

        /// The weight field's label for VoiceOver and Voice Control; %@ is the category's name
        /// from Canvas (for example "Homework").
        public static func weightLabel(_ category: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.weightLabel", defaultValue: "Weight for \(category), percent of grade",
                bundle: #bundle,
                comment: "Accessibility label of a number field in the what-if calculator. The placeholder is the name of an assignment category from Canvas.")
        }

        /// %@ is the weights' total, already formatted as a percentage ("100%").
        public static func total(_ total: String) -> LocalizedStringResource {
            LocalizedStringResource("courseDetail.whatIf.estimate.total", defaultValue: "Total: \(total)", bundle: #bundle,
                                    comment: "The sum of the category weights in the what-if calculator. The placeholder is a percentage, for example 100%.")
        }

        public static func invalidWeight() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.invalidWeight",
                defaultValue: "Enter a number from 0 to 100. Until then, this category uses its setting in Canvas.",
                bundle: #bundle, comment: "Under a category weight the student typed that is not a number from 0 to 100.")
        }

        public static func allZero() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.allZero",
                defaultValue: "At least one category needs a weight above 0. Until then, Tally uses this course's setting in Canvas.",
                bundle: #bundle, comment: "In the what-if calculator, when every category weight the student set or left is 0.")
        }

        public static func overHundred() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.overHundred",
                defaultValue: "These weights add up to more than 100%, so the estimate can come out higher than your real grade.",
                bundle: #bundle, comment: "In the what-if calculator, when the category weights add up to more than 100 percent.")
        }

        /// What VoiceOver reads for the summary before any score is typed (the screen shows a dash).
        public static func noEstimate() -> LocalizedStringResource {
            LocalizedStringResource(
                "courseDetail.whatIf.estimate.none", defaultValue: "No estimate yet. Enter a score to see one.", bundle: #bundle,
                comment: "Accessibility label of the what-if calculator's summary when there is no grade to estimate yet.")
        }
    }
}
