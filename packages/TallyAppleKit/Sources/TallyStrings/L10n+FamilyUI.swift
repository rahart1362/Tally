import Foundation

/// Family linking's screens (M3-E2: FAM-09 switcher, FAM-10 Settings, FAM-14 sample family;
/// family-linking.md §7). A file of its own, beside M3-E1's `L10n+Family.swift` (the parent
/// notifications), so neither stream edits the other's file. Every function whose arguments are all
/// `String`s takes them unlabelled, so per-row code can look it up through `L10n.string(...)`
/// (rule 13). Names are a student's or an observer's name from Canvas; never a grade.
extension L10n {
    public enum FamilyUI {
        // MARK: Header student-switcher (§7.1)

        public static func viewing(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.switcher.viewing", defaultValue: "Viewing \(name)", bundle: #bundle,
                                    comment: "VoiceOver label of the header student-switcher in parent mode. The argument is the first name of the student whose data is shown.")
        }

        public static func switchHint() -> LocalizedStringResource {
            LocalizedStringResource("family.switcher.hint", defaultValue: "Double-tap to switch student", bundle: #bundle,
                                    comment: "VoiceOver hint of the header student-switcher when the parent has more than one linked student.")
        }

        public static func nowViewing(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.switcher.nowViewing", defaultValue: "Now viewing \(name)", bundle: #bundle,
                                    comment: "VoiceOver announcement after the parent switches student. The argument is the student's first name.")
        }

        public static func pickerLabel() -> LocalizedStringResource {
            LocalizedStringResource("family.switcher.picker", defaultValue: "Student", bundle: #bundle,
                                    comment: "Label of the list of linked students inside the header switcher's menu.")
        }

        public static func manageLinkedStudents() -> LocalizedStringResource {
            LocalizedStringResource("family.switcher.manage", defaultValue: "Manage linked students…", bundle: #bundle,
                                    comment: "Header switcher menu item: opens Settings, where the linked students are listed.")
        }

        public static func addStudentEllipsis() -> LocalizedStringResource {
            LocalizedStringResource("family.switcher.add", defaultValue: "Add a student…", bundle: #bundle,
                                    comment: "Header switcher menu item: starts adding another student with a code.")
        }

        // MARK: Parent: Linked students (§7.3)

        public static func linkedStudentsHeader() -> LocalizedStringResource {
            LocalizedStringResource("family.linked.header", defaultValue: "Linked Students", bundle: #bundle,
                                    comment: "Settings section header in parent mode: the students this parent observes in Canvas.")
        }

        public static func viewedStudent() -> LocalizedStringResource {
            LocalizedStringResource("family.linked.viewed", defaultValue: "Viewing", bundle: #bundle,
                                    comment: "VoiceOver value of the linked-student row whose data the app is showing now.")
        }

        public static func addStudent() -> LocalizedStringResource {
            LocalizedStringResource("family.linked.addStudent", defaultValue: "Add a Student", bundle: #bundle,
                                    comment: "Button: link another student to this parent account with the student's code.")
        }

        public static func hideStudentNames() -> LocalizedStringResource {
            LocalizedStringResource("family.linked.hideNames", defaultValue: "Hide Student Names", bundle: #bundle,
                                    comment: "Toggle: parent notifications say 'Your student' instead of the student's name.")
        }

        public static func linkedStudentsFooter() -> LocalizedStringResource {
            LocalizedStringResource("family.linked.footer", defaultValue: "Notifications about your students never include grades.", bundle: #bundle,
                                    comment: "Footer under the Linked Students section in parent mode.")
        }

        public static func notificationsFor(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.detail.notificationsHeader", defaultValue: "Notifications for \(name)", bundle: #bundle,
                                    comment: "Section header on one linked student's page. The argument is the student's first name.")
        }

        public static func notifyWeekAhead() -> LocalizedStringResource {
            LocalizedStringResource("family.detail.weekAhead", defaultValue: "Week Ahead", bundle: #bundle,
                                    comment: "Toggle: the Sunday evening summary of what the student has due in the next 7 days.")
        }

        public static func notifyMissingStillOpen() -> LocalizedStringResource {
            LocalizedStringResource("family.detail.missing", defaultValue: "Missing Work Still Accepted", bundle: #bundle,
                                    comment: "Toggle: tell the parent when the student's work is past due but Canvas still accepts it.")
        }

        public static func notifyGradePosted() -> LocalizedStringResource {
            LocalizedStringResource("family.detail.gradePosted", defaultValue: "New Grade Posted", bundle: #bundle,
                                    comment: "Toggle: tell the parent a new grade was posted (the grade itself is never shown).")
        }

        public static func notifyDueReminders() -> LocalizedStringResource {
            LocalizedStringResource("family.detail.dueReminders", defaultValue: "Due-Date Reminders", bundle: #bundle,
                                    comment: "Toggle: remind the parent before the student's work is due. Off by default; the student gets their own reminders.")
        }

        public static func removeFromTally() -> LocalizedStringResource {
            LocalizedStringResource("family.detail.remove", defaultValue: "Remove from Tally", bundle: #bundle,
                                    comment: "Button on a linked student's page: delete that student's data from this iPhone; the Canvas link stays. Also the confirmation's button.")
        }

        public static func unlinkInCanvas() -> LocalizedStringResource {
            LocalizedStringResource("family.detail.unlink", defaultValue: "Unlink in Canvas", bundle: #bundle,
                                    comment: "Destructive button on a linked student's page: remove the observer link in Canvas itself.")
        }

        // MARK: Confirmations (§7.7, verbatim but for the name)

        public static func unlinkTitle(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.unlink.title", defaultValue: "Unlink \(name)?", bundle: #bundle,
                                    comment: "Confirmation title before the parent removes the Canvas link to a student. The argument is the student's first name.")
        }

        public static func unlinkMessage(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.unlink.message", defaultValue: "You'll stop seeing \(name)'s courses and grades in Tally, the Canvas Parent app and Canvas on the web. To link again, \(name) will need to send you a new code. Tally will delete \(name)'s saved data from this iPhone.", bundle: #bundle,
                                    comment: "Confirmation message before unlinking a student in Canvas. Every argument is the same student's first name.")
        }

        public static func unlinkConfirm() -> LocalizedStringResource {
            LocalizedStringResource("family.unlink.confirm", defaultValue: "Unlink", bundle: #bundle,
                                    comment: "Destructive confirmation button: remove the Canvas observer link to the student.")
        }

        public static func removeTitle(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.remove.title", defaultValue: "Remove \(name) from Tally?", bundle: #bundle,
                                    comment: "Confirmation title before the parent removes a student's data from this iPhone. The argument is the student's first name.")
        }

        public static func removeMessage(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.remove.message", defaultValue: "\(name) stays linked to your Canvas account. Tally will delete \(name)'s saved data from this iPhone. You can add \(name) back from Linked students.", bundle: #bundle,
                                    comment: "Confirmation message before removing a student from Tally only. Every argument is the same student's first name.")
        }

        // MARK: Student: Family & Sharing (§7.2)

        public static func sharingHeader() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.header", defaultValue: "Family & Sharing", bundle: #bundle,
                                    comment: "Settings section header for a student: who can see their Canvas, and inviting a parent.")
        }

        public static func sharingExplainer() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.explainer", defaultValue: "People linked to your Canvas account as observers (such as parents) can see your courses, assignments and grades in Canvas and in apps like Tally. They can't submit work or act as you.", bundle: #bundle,
                                    comment: "Explanation at the top of a student's Family & Sharing section.")
        }

        public static func invite() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.invite", defaultValue: "Invite a Parent", bundle: #bundle,
                                    comment: "Button for a student: create a one-time code a parent uses to link to the student's Canvas account.")
        }

        public static func linkedInCanvasHeader() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.linkedHeader", defaultValue: "Linked in Canvas", bundle: #bundle,
                                    comment: "Subheading over the list of observers linked to the student's Canvas account.")
        }

        public static func linkedInCanvasFooter() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.linkedFooter", defaultValue: "Only account-wide links are shown. Links your school made for a single course may not appear.", bundle: #bundle,
                                    comment: "Footnote under the list of observers linked to the student's Canvas account.")
        }

        public static func linkedToYourAccount() -> LocalizedStringResource {
            LocalizedStringResource("family.observer.linked", defaultValue: "Linked to your Canvas account", bundle: #bundle,
                                    comment: "On one observer's page: this person is linked to the student's Canvas account.")
        }

        public static func howToRemove() -> LocalizedStringResource {
            LocalizedStringResource("family.observer.howToRemove", defaultValue: "How to Remove", bundle: #bundle,
                                    comment: "Button on one observer's page: explains that only the school can remove an observer.")
        }

        public static func howToRemoveHeading() -> LocalizedStringResource {
            LocalizedStringResource("family.observer.howToRemoveHeading", defaultValue: "Only your school can remove an observer.", bundle: #bundle,
                                    comment: "Heading of the sheet explaining how a student gets an observer removed.")
        }

        public static func howToRemoveBody(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.observer.howToRemoveBody", defaultValue: "Canvas doesn't let students unlink observers. Contact your school's Canvas support and ask them to remove \(name) as an observer on your account.", bundle: #bundle,
                                    comment: "Body of the how-to-remove sheet. The argument is the observer's name.")
        }

        public static func copyRequest() -> LocalizedStringResource {
            LocalizedStringResource("family.observer.copyRequest", defaultValue: "Copy Request", bundle: #bundle,
                                    comment: "Button: copy a ready-written request to the school to remove an observer.")
        }

        public static func removalRequest(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.observer.request", defaultValue: "Please remove \(name) as an observer on my Canvas account.", bundle: #bundle,
                                    comment: "Text the student pastes into a message to their school. The argument is the observer's name.")
        }

        public static func invitesHeader() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.invitesHeader", defaultValue: "Invites from This iPhone", bundle: #bundle,
                                    comment: "Subheading over the pairing codes this student created on this iPhone.")
        }

        public static func invitesFooter() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.invitesFooter", defaultValue: "Codes can't be cancelled. They stop working after 7 days or once used.", bundle: #bundle,
                                    comment: "Footnote under the student's pairing codes.")
        }

        public static func expires(_ date: String) -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.expires", defaultValue: "Expires \(date)", bundle: #bundle,
                                    comment: "When a pairing code stops working. The argument is a formatted date, such as 'Fri, Oct 2'.")
        }

        public static func shareAgain() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.shareAgain", defaultValue: "Share Again", bundle: #bundle,
                                    comment: "Button: share a pairing code the student already created.")
        }

        public static func inviteFallbackLabel() -> LocalizedStringResource {
            LocalizedStringResource("family.sharing.inviteLabel", defaultValue: "Code", bundle: #bundle,
                                    comment: "Row title for a pairing code the student did not give a name.")
        }

        // MARK: Invite flow (§7.4)

        public static func inviteTitle() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.title", defaultValue: "Let a parent see your Canvas", bundle: #bundle,
                                    comment: "Title of the sheet where a student creates a code for a parent.")
        }

        public static func inviteWillSee() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.willSee", defaultValue: "They'll see your courses, assignments and due dates, grades and comments, announcements and calendar.", bundle: #bundle,
                                    comment: "Invite sheet: what a linked parent can see in Canvas.")
        }

        public static func inviteCannot() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.cannot", defaultValue: "They can't submit work, message as you or change anything.", bundle: #bundle,
                                    comment: "Invite sheet: what a linked parent can't do.")
        }

        public static func inviteOwnAccount() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.ownAccount", defaultValue: "Your parent signs in with their own account. You never share your password.", bundle: #bundle,
                                    comment: "Invite sheet: the parent uses their own Canvas parent account.")
        }

        public static func inviteLabelField() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.labelField", defaultValue: "Who's this for? (only on this iPhone)", bundle: #bundle,
                                    comment: "Optional text field on the invite sheet: a private label for the code, such as 'Mom'. Kept on this iPhone only.")
        }

        public static func createCode() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.create", defaultValue: "Create Code", bundle: #bundle,
                                    comment: "Button: ask Canvas for a one-time pairing code.")
        }

        public static func worksOnce(_ date: String) -> LocalizedStringResource {
            LocalizedStringResource("family.invite.worksOnce", defaultValue: "Works once · expires \(date)", bundle: #bundle,
                                    comment: "Under a new pairing code. The argument is a formatted date, such as 'Fri, Oct 2'.")
        }

        public static func codeWarning() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.warning", defaultValue: "Anyone who enters this code first will be linked to you. Share it only with your parent.", bundle: #bundle,
                                    comment: "Warning under a new pairing code.")
        }

        public static func oldestCodeWarning() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.oldestWarning", defaultValue: "Creating another code turns off your oldest unused one.", bundle: #bundle,
                                    comment: "Shown before Create Code when 5 codes from this iPhone are still pending.")
        }

        public static func share() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.share", defaultValue: "Share…", bundle: #bundle,
                                    comment: "Button: open the share sheet with the pairing code and instructions.")
        }

        public static func copy() -> LocalizedStringResource {
            LocalizedStringResource("family.invite.copy", defaultValue: "Copy", bundle: #bundle,
                                    comment: "Button: copy the pairing code.")
        }

        public static func codeAccessibility(_ spelled: String) -> LocalizedStringResource {
            LocalizedStringResource("family.invite.codeAccessibility", defaultValue: "Code: \(spelled)", bundle: #bundle,
                                    comment: "VoiceOver label of a pairing code. The argument spells the code one character at a time, such as 'X, 7, Q, 2, K, P'.")
        }

        public static func shareMessage(_ school: String, _ code: String, _ date: String) -> LocalizedStringResource {
            LocalizedStringResource("family.invite.shareText", defaultValue: "I'd like you to see my \(school) Canvas in Tally.\n1. Get Tally from the App Store.\n2. Choose \(school), then \"I'm a parent\".\n3. Sign in or create your parent account.\n4. Enter code \(code) (case-sensitive, expires \(date)).", bundle: #bundle,
                                    comment: "Text the student shares with a parent. 1 and 2: the school's name. 3: the pairing code. 4: a formatted date. Never contains grades; the code is never part of a link.")
        }

        public static func shareMessageNoSchool(_ code: String, _ date: String) -> LocalizedStringResource {
            LocalizedStringResource("family.invite.shareTextNoSchool", defaultValue: "I'd like you to see my Canvas in Tally.\n1. Get Tally from the App Store.\n2. Choose my school, then \"I'm a parent\".\n3. Sign in or create your parent account.\n4. Enter code \(code) (case-sensitive, expires \(date)).", bundle: #bundle,
                                    comment: "Text the student shares with a parent when Tally doesn't know the school's name. 1: the pairing code. 2: a formatted date. Never contains grades; the code is never part of a link.")
        }

        public static func yourSchool() -> LocalizedStringResource {
            LocalizedStringResource("family.state.yourSchool", defaultValue: "Your school", bundle: #bundle,
                                    comment: "Stands for the school's name in a family-linking message when Tally doesn't know it, as in 'Your school hasn't turned on parent accounts in Canvas'.")
        }

        // MARK: Add a student (§7.5 step 4)

        public static func addStudentTitle() -> LocalizedStringResource {
            LocalizedStringResource("family.add.title", defaultValue: "Add a Student", bundle: #bundle,
                                    comment: "Title of the sheet where a parent enters a student's pairing code.")
        }

        public static func codeField() -> LocalizedStringResource {
            LocalizedStringResource("family.add.codeField", defaultValue: "Code from your student", bundle: #bundle,
                                    comment: "Text field for the pairing code a student created.")
        }

        public static func codeFieldFooter() -> LocalizedStringResource {
            LocalizedStringResource("family.add.footer", defaultValue: "Codes are case-sensitive. Ask your student for the code from Tally (Settings → Family & Sharing) or from Canvas.", bundle: #bundle,
                                    comment: "Footnote under the pairing code field.")
        }

        public static func add() -> LocalizedStringResource {
            LocalizedStringResource("family.add.confirm", defaultValue: "Add", bundle: #bundle,
                                    comment: "Button: link the student with the entered code.")
        }

        // MARK: Empty and error states (§7.6)

        public static func parentNoStudents() -> LocalizedStringResource {
            LocalizedStringResource("family.state.parentNoStudents", defaultValue: "No students linked yet. Ask your student for a code from Tally (Settings → Family & Sharing) or from Canvas (Account → Settings → Pair with Observer).", bundle: #bundle,
                                    comment: "Parent mode with no linked student.")
        }

        public static func studentNoObservers() -> LocalizedStringResource {
            LocalizedStringResource("family.state.studentNoObservers", defaultValue: "No one is linked to your Canvas account.", bundle: #bundle,
                                    comment: "A student's Family & Sharing section when no observer is linked.")
        }

        public static func codeRejected() -> LocalizedStringResource {
            LocalizedStringResource("family.state.codeRejected", defaultValue: "That code didn't work. Codes are case-sensitive, work once, and expire after 7 days. Ask your student for a new one.", bundle: #bundle,
                                    comment: "Canvas refused the pairing code a parent entered.")
        }

        public static func inviteRefused(_ school: String) -> LocalizedStringResource {
            LocalizedStringResource("family.state.inviteRefused", defaultValue: "\(school) hasn't turned on parent accounts in Canvas, so Tally can't create an invite.", bundle: #bundle,
                                    comment: "Canvas refused to create a pairing code because the school doesn't allow parent accounts. The argument is the school's name.")
        }

        public static func scopeMissing() -> LocalizedStringResource {
            LocalizedStringResource("family.state.scopeMissing", defaultValue: "Your school's Tally setup doesn't include parent invites yet.", bundle: #bundle,
                                    comment: "The school's Tally setup lacks the family permissions, so Tally can't create or use codes.")
        }

        public static func throttled() -> LocalizedStringResource {
            LocalizedStringResource("family.state.throttled", defaultValue: "You've created the most codes Tally allows in a day. Try again tomorrow.", bundle: #bundle,
                                    comment: "The student reached Tally's daily limit of pairing codes.")
        }

        public static func networkProblem() -> LocalizedStringResource {
            LocalizedStringResource("family.state.network", defaultValue: "Tally couldn't reach Canvas. Check your connection and try again.", bundle: #bundle,
                                    comment: "A family-linking request to Canvas failed for a network or server reason.")
        }

        public static func tryAgain() -> LocalizedStringResource {
            LocalizedStringResource("family.state.tryAgain", defaultValue: "Try Again", bundle: #bundle,
                                    comment: "Button after a failed family-linking request.")
        }

        public static func getCodeInCanvas() -> LocalizedStringResource {
            LocalizedStringResource("family.state.getCodeInCanvas", defaultValue: "Get a Code in Canvas", bundle: #bundle,
                                    comment: "Button: open the school's Canvas settings in Safari, where a student can create a pairing code.")
        }

        public static func linkRemovedTitle() -> LocalizedStringResource {
            LocalizedStringResource("family.state.linkRemovedTitle", defaultValue: "Link Removed", bundle: #bundle,
                                    comment: "Alert title when a student's Canvas link to this parent disappeared.")
        }

        public static func linkRemoved(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("family.state.linkRemoved", defaultValue: "You're no longer linked to \(name) in Canvas. Tally removed \(name)'s saved data from this iPhone.", bundle: #bundle,
                                    comment: "Alert message when a student's Canvas link to this parent disappeared. Both arguments are the student's first name.")
        }

        public static func ok() -> LocalizedStringResource {
            LocalizedStringResource("family.state.ok", defaultValue: "OK", bundle: #bundle,
                                    comment: "Button closing the link-removed alert.")
        }

        // MARK: Sample data (FAM-14)

        public static func sampleViewAsParent() -> LocalizedStringResource {
            LocalizedStringResource("family.sample.viewAsParent", defaultValue: "Explore Parent Mode", bundle: #bundle,
                                    comment: "Sample data only: show the app as a parent who observes two fictional students.")
        }

        public static func sampleViewAsParentFooter() -> LocalizedStringResource {
            LocalizedStringResource("family.sample.viewAsParentFooter", defaultValue: "See Tally as a parent who observes two fictional students.", bundle: #bundle,
                                    comment: "Sample data only: footnote under Explore Parent Mode.")
        }

        public static func sampleViewAsStudent() -> LocalizedStringResource {
            LocalizedStringResource("family.sample.viewAsStudent", defaultValue: "Explore Student Mode", bundle: #bundle,
                                    comment: "Sample data only: return from the parent view to the fictional student's own view.")
        }
    }
}
