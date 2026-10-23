import Foundation

/// FEAT-4 (ideas 2 and 6): Course Detail's "Set a goal" entry and What-If's one-tap "Save as
/// goal". Kept in its own file, beside `L10n.swift`, for the same reason `L10n+GradeControls.swift`
/// is: this work package's additions never touch the lines another stream adds there, and every
/// key is in the same catalog.
extension L10n.CourseDetail {
    /// Idea 2: the goal section's header, above the "Set a goal" button or the stepper.
    public static func goalHeader() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.goal.header", defaultValue: "Course goal", bundle: #bundle,
                                comment: "Course Detail, Overview: the per-course grade goal section's header.")
    }

    /// Idea 2: explains what the goal is for, under the button or the stepper.
    public static func goalFooter() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.goal.footer",
            defaultValue: "Tally shows this course as needing attention once it drops below your goal.",
            bundle: #bundle, comment: "Course Detail, Overview: the per-course grade goal section's footer.")
    }

    /// Idea 2: the entry point before any goal is set.
    public static func goalSetButton() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.goal.setButton", defaultValue: "Set a goal", bundle: #bundle,
                                comment: "Course Detail, Overview: the button that starts a per-course grade goal.")
    }

    /// Idea 2: the stepper's row label once a goal is set. The placeholder is an already-formatted
    /// whole-number percentage, such as "90%".
    public static func goalStepperLabel(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.goal.stepperLabel", defaultValue: "Goal: \(percent)", bundle: #bundle,
                                comment: "Course Detail, Overview: the per-course grade goal stepper's row label.")
    }

    /// Idea 2: clears the goal back to none.
    public static func goalRemove() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.goal.remove", defaultValue: "Remove goal", bundle: #bundle,
                                comment: "Course Detail, Overview: the button that clears the per-course grade goal.")
    }

    /// Idea 2: VoiceOver announcement after removing the goal (the same pattern as To-Do's
    /// "Remind me" confirmation, `L10n.ToDo.remindMeConfirmation`).
    public static func goalRemovedConfirmation() -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.goal.removedConfirmation", defaultValue: "Goal removed", bundle: #bundle,
                                comment: "VoiceOver announcement after removing the per-course grade goal.")
    }

    /// Idea 6: the what-if sheet's one-tap save, next to the existing goal-seek stepper. The
    /// placeholder is an already-formatted whole-number percentage, such as "90%".
    public static func whatIfSaveAsGoalButton(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource("courseDetail.whatIf.saveAsGoalButton", defaultValue: "Set \(percent) as my goal", bundle: #bundle,
                                comment: "The what-if sheet's goal-mode section: saves the target percentage above as this course's goal.")
    }

    /// Idea 6: VoiceOver announcement after saving (the same pattern as To-Do's "Remind me"
    /// confirmation). The placeholder is an already-formatted whole-number percentage.
    public static func whatIfGoalSavedConfirmation(_ percent: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.goalSavedConfirmation", defaultValue: "Set \(percent) as your goal", bundle: #bundle,
            comment: "VoiceOver announcement after saving the what-if target as this course's goal.")
    }
}
