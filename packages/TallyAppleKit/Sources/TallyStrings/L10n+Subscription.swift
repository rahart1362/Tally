import Foundation

/// M3-B2 (PAY-05, 06, 08, 09, 10, 11): the paywall, Settings → Subscription, the sample-mode
/// interstitial, the locked-tab card, the "Subscribe to refresh" notice, the school-revoked notice and
/// the erase note. A file of its own, as `L10n+Family.swift` is, so `L10n.swift` stays untouched while
/// other streams edit it. **Prices are never here:** the App Store formats them (`Product.displayPrice`),
/// and these sentences only place that text. Every English value is a draft for the owner
/// (docs/pmo/reviews/m3b2-report.md).
extension L10n {
    public enum Subscription {
        public static func name() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.name.student", defaultValue: "Tally Annual", bundle: #bundle,
                comment: "The name of Tally's student subscription, as the App Store sells it (PRD §11.1). The paywall's title and the plan in Settings > Subscription.")
        }

        public static func duration(_ period: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.duration", defaultValue: "Subscription length: \(period)", bundle: #bundle,
                comment: "Paywall, under the title: how long one subscription period lasts (Apple requires the length on the paywall). The argument is a length such as '1 year'.")
        }

        public static func days(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.period.days", defaultValue: "\(count) days", bundle: #bundle,
                comment: "A length of time in days, such as '1 day', used inside other subscription sentences: the subscription length and the free trial's length.")
        }

        public static func weeks(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.period.weeks", defaultValue: "\(count) weeks", bundle: #bundle,
                comment: "A length of time in weeks, such as '1 week', used inside other subscription sentences: the subscription length and the free trial's length.")
        }

        public static func months(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.period.months", defaultValue: "\(count) months", bundle: #bundle,
                comment: "A length of time in months, such as '1 month', used inside other subscription sentences: the subscription length and the free trial's length.")
        }

        public static func years(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.period.years", defaultValue: "\(count) years", bundle: #bundle,
                comment: "A length of time in years, such as '1 year', used inside other subscription sentences: the subscription length and the free trial's length.")
        }

        public static func pricePerYear(_ price: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.price.perYear", defaultValue: "\(price)/year", bundle: #bundle,
                comment: "Paywall: the subscription's price, its most prominent text. The argument is the App Store's own price text, such as '$9.99'; never reformat it.")
        }

        public static func pricePerYearSpoken(_ price: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.price.perYear.spoken", defaultValue: "\(price) per year", bundle: #bundle,
                comment: "VoiceOver label of the paywall's price (the visible text is '$9.99/year'). The argument is the App Store's price text, such as '$9.99'.")
        }

        public static func priceEvery(_ price: String, _ period: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.price.every", defaultValue: "\(price) every \(period)", bundle: #bundle,
                comment: "Paywall price for a period other than one year. 1: the App Store's price text, such as '$9.99'. 2: a length, such as '6 months'.")
        }

        public static func trial(_ trial: String, then price: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.trial", defaultValue: "\(trial) free, then \(price)", bundle: #bundle,
                comment: "Paywall, only when this Apple Account can get the free trial. 1: the trial's length, such as '1 month'. 2: the price per period, such as '$9.99/year'.")
        }

        public static func renewal() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.renewal", defaultValue: "Renews automatically until you cancel. Cancel anytime in Settings at least 24 hours before it renews.", bundle: #bundle,
                comment: "Paywall: the auto-renewal disclosure under the price.")
        }

        public static func includedHeader() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.included", defaultValue: "What's included", bundle: #bundle,
                comment: "Paywall: the heading above the list of what the subscription includes.")
        }

        public static func featureGrades() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.feature.grades", defaultValue: "Grades and what-if for every course", bundle: #bundle,
                comment: "Paywall, what's included: the grade features. Never shown to a school whose grades are not in Canvas.")
        }

        public static func featureDueDates() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.feature.dueDates", defaultValue: "Due dates, To-Do and Calendar, kept up to date", bundle: #bundle,
                comment: "Paywall, what's included: assignments and the calendar, refreshed from Canvas.")
        }

        public static func featureReminders() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.feature.reminders", defaultValue: "Reminders before work is due", bundle: #bundle,
                comment: "Paywall, what's included: due-date reminders.")
        }

        public static func featureInsights() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.feature.insights", defaultValue: "Insights, widgets and Shortcuts", bundle: #bundle,
                comment: "Paywall, what's included: the Insights tab, Home Screen widgets and Shortcuts.")
        }

        public static func featureWorkload() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.feature.workload", defaultValue: "Workload insights, widgets and Shortcuts", bundle: #bundle,
                comment: "Paywall, what's included, for a school whose grades are not in Canvas: insights about the workload (no grades), widgets and Shortcuts.")
        }

        public static func featurePrivacy() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.feature.privacy", defaultValue: "Your data stays on this iPhone", bundle: #bundle,
                comment: "Paywall, what's included: Tally has no server; the student's Canvas data stays on the device.")
        }

        public static func startFreeTrial() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.startFreeTrial", defaultValue: "Start Free Trial", bundle: #bundle,
                comment: "Paywall's purchase button when this Apple Account can get the free trial.")
        }

        public static func subscribe() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.subscribe", defaultValue: "Subscribe", bundle: #bundle,
                comment: "Paywall's purchase button when there is no free trial for this Apple Account.")
        }

        public static func restorePurchases() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.restorePurchases", defaultValue: "Restore Purchases", bundle: #bundle,
                comment: "Button that asks the App Store for this Apple Account's purchases again (paywall, Settings > Subscription).")
        }

        public static func redeemCode() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.redeemCode", defaultValue: "Redeem Code", bundle: #bundle,
                comment: "Button that opens Apple's sheet for redeeming an offer code (paywall, Settings > Subscription).")
        }

        public static func termsOfUse() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.termsOfUse", defaultValue: "Terms of Use", bundle: #bundle,
                comment: "Paywall link to Tally's Terms of Use.")
        }

        public static func privacyPolicy() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.privacyPolicy", defaultValue: "Privacy Policy", bundle: #bundle,
                comment: "Paywall link to Tally's Privacy Policy.")
        }

        public static func notNow() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.notNow", defaultValue: "Not Now", bundle: #bundle,
                comment: "Paywall button that closes it without buying.")
        }

        public static func loading() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.loading", defaultValue: "Checking the App Store", bundle: #bundle,
                comment: "Paywall, while the price loads from the App Store (a progress indicator's label).")
        }

        public static func unavailable() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.unavailable", defaultValue: "The App Store isn't available right now. Check your connection and try again.", bundle: #bundle,
                comment: "Paywall, when the App Store returned no price.")
        }

        public static func tryAgain() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.tryAgain", defaultValue: "Try Again", bundle: #bundle,
                comment: "Paywall button that asks the App Store for the price again.")
        }

        public static func pending() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.pending", defaultValue: "Waiting for approval. Tally unlocks as soon as your purchase is approved.", bundle: #bundle,
                comment: "Paywall, after Ask to Buy: the purchase waits for a parent's approval.")
        }

        public static func failed() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.failed", defaultValue: "The purchase didn't finish. Try again, or use Restore Purchases.", bundle: #bundle,
                comment: "Paywall, after a purchase failed or could not be verified.")
        }

        public static func nothingToRestore() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.nothingToRestore", defaultValue: "There's no Tally subscription to restore for this Apple Account.", bundle: #bundle,
                comment: "After Restore Purchases found no Tally subscription.")
        }

        public static func restoreFailed() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.paywall.restoreFailed", defaultValue: "Couldn't reach the App Store to restore purchases. Try again later.", bundle: #bundle,
                comment: "After Restore Purchases could not reach the App Store.")
        }

        public static func interstitialTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.interstitial.title", defaultValue: "Tally works at enabled schools", bundle: #bundle,
                comment: "Sample data, Settings > Subscription > See Plans: the title of the note shown before the plans.")
        }

        public static func interstitialMessage() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.interstitial.message", defaultValue: "Tally Annual works at schools where Tally is enabled. Check that yours is one of them before you subscribe.", bundle: #bundle,
                comment: "Sample data: the note shown before the plans (App Review sees it too).")
        }

        public static func checkMySchool() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.interstitial.checkMySchool", defaultValue: "Check My School", bundle: #bundle,
                comment: "Sample data note's button: leaves the sample data to find the student's school.")
        }

        public static func continueToPlans() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.interstitial.continue", defaultValue: "Continue", bundle: #bundle,
                comment: "Sample data note's button: goes on to the plans.")
        }

        public static func settingsTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.settings.title", defaultValue: "Subscription", bundle: #bundle,
                comment: "Settings row and page title for the subscription.")
        }

        public static func planLabel() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.settings.plan", defaultValue: "Plan", bundle: #bundle,
                comment: "Settings > Subscription: the label of the row naming the plan.")
        }

        public static func statusLabel() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.settings.status", defaultValue: "Status", bundle: #bundle,
                comment: "Settings > Subscription: the label of the row with the subscription's state.")
        }

        public static func statusActive(until date: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.status.active", defaultValue: "Active until \(date)", bundle: #bundle,
                comment: "Subscription state. The argument is a date, such as 'Oct 2, 2027' (the end of the current period; it renews unless cancelled).")
        }

        public static func statusNotSubscribed() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.status.notSubscribed", defaultValue: "Not subscribed", bundle: #bundle,
                comment: "Subscription state: no trial or subscription on this Apple Account.")
        }

        public static func statusSchool(until date: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.status.school", defaultValue: "Provided by your school until \(date)", bundle: #bundle,
                comment: "M3-B3: subscription state when the account's only entitlement is a school-assigned seat, not this Apple Account's own purchase (owner decision 2026-10-02). The argument is a date, such as 'Oct 2, 2027'.")
        }

        public static func statusEnded(_ date: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.status.ended", defaultValue: "Ended \(date)", bundle: #bundle,
                comment: "Subscription state after it ended or was refunded. The argument is a date, such as 'Sep 30, 2026'.")
        }

        public static func statusPending() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.status.pending", defaultValue: "Waiting for approval", bundle: #bundle,
                comment: "Subscription state after Ask to Buy, until a parent approves.")
        }

        public static func statusChecking() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.status.checking", defaultValue: "Checking", bundle: #bundle,
                comment: "Subscription state before the App Store has answered.")
        }

        public static func seePlans() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.seePlans", defaultValue: "See Plans", bundle: #bundle,
                comment: "Button that opens the paywall (Settings > Subscription, a locked tab's card, the 'Subscribe to refresh' notice).")
        }

        public static func manage() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.manage", defaultValue: "Manage Subscription", bundle: #bundle,
                comment: "Button that opens Apple's subscription management sheet (cancel, change).")
        }

        public static func requestRefund() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.requestRefund", defaultValue: "Request a Refund", bundle: #bundle,
                comment: "Button that opens Apple's refund request sheet. Tally cannot refund; Apple decides.")
        }

        public static func noRefund() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.settings.noRefund", defaultValue: "There's no Tally purchase on this Apple Account to refund.", bundle: #bundle,
                comment: "Settings > Subscription, after Request a Refund found no purchase.")
        }

        public static func settingsFooter() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.settings.footer", defaultValue: "Your subscription belongs to your Apple Account, so it stays with you if you move to another school where Tally is enabled. Apple handles payment, renewals and refunds.", bundle: #bundle,
                comment: "Settings > Subscription footer (PRD §11.4).")
        }

        public static func settingsFooterSchool() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.settings.footerSchool", defaultValue: "Your school provides this subscription through Apple. For questions about it, ask your school.", bundle: #bundle,
                comment: "M3-B3: Settings > Subscription footer when the account's only entitlement is a school-assigned seat, replacing the Apple-Account footer (owner decision 2026-10-02).")
        }

        public static func lockedTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.locked.title", defaultValue: "Part of Tally Annual", bundle: #bundle,
                comment: "A locked tab's card (Courses, Calendar, To-Do, Insights) for a student without a trial or subscription.")
        }

        public static func lockedBody() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.locked.body", defaultValue: "Courses, Calendar, To-Do and Insights come with a subscription. Your Dashboard stays free.", bundle: #bundle,
                comment: "A locked tab's card, under its title.")
        }

        public static func bannerSavedFrom(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.banner.savedFrom", defaultValue: "Subscribe to refresh — showing saved data from \(time).", bundle: #bundle,
                comment: "Above the Home's tabs when there is no trial or subscription: refresh is off and the saved data is shown (PRD §11.2). The argument is when the data was saved, such as 'Sep 30, 2:14 PM'.")
        }

        public static func bannerNoDate() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.banner.noDate", defaultValue: "Subscribe to refresh.", bundle: #bundle,
                comment: "The same notice when the time of the saved data is not known.")
        }

        public static func schoolOffTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.schoolOff.title", defaultValue: "Your school turned off Tally", bundle: #bundle,
                comment: "Full-screen notice when the school's Canvas rejects Tally (the school disabled Tally's access) while the student has a subscription.")
        }

        public static func schoolOffBody() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.schoolOff.body", defaultValue: "Your school's Canvas no longer lets Tally connect, so Tally can't refresh. Your saved data stays readable. Your subscription is still active: you can cancel it, or ask Apple for a refund.", bundle: #bundle,
                comment: "The school-revoked notice's text.")
        }

        public static func schoolOffBodySeat() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.schoolOff.bodySeat", defaultValue: "Your school's Canvas no longer lets Tally connect, so Tally can't refresh. Your saved data stays readable.", bundle: #bundle,
                comment: "M3-B3: the school-revoked notice's text when the account's only entitlement is a school-assigned seat, without the cancel/refund sentence (the school, not the student, holds that purchase).")
        }

        public static func schoolOffContinue() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.schoolOff.continue", defaultValue: "Continue with Saved Data", bundle: #bundle,
                comment: "The school-revoked notice's button that closes it and shows the saved data.")
        }

        public static func eraseKeepsSubscription() -> LocalizedStringResource {
            LocalizedStringResource(
                "subscription.erase.note", defaultValue: "This doesn't cancel your Tally subscription. To cancel it, choose Manage Subscription.", bundle: #bundle,
                comment: "Added to the Sign Out & Erase confirmation (PAY-11): erasing Tally's data leaves the App Store subscription as it is.")
        }
    }
}
