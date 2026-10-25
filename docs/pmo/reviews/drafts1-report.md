# DRAFTS-1 report: pre-submission policy drafts (EB-05, EB-27, EB-28, EB-29)

**Status: DRAFT. Not legal advice.** Every page is a draft for the owner's line-by-line approval and counsel's review (owner item O7), marked `DRAFT-PENDING-LEGAL-REVIEW` the way `site/privacy/index.html` is. Branch `site/drafts-1` (from `origin/main` `d8ab0c3`), pushed; **no PR**: merging to `main` publishes the site (`site/CNAME`), so the PMO opens the PR after the owner approves. **Correction (DOCS-5, 2026-10-25): this was wrong.** Merging to `main` does not publish or host anything by itself — `tally-app.dev` has no DNS record and GitHub Pages is not enabled (confirmed: the Pages API returns 404). Hosting is a separate, owner-driven step, `docs/GO-LIVE.md` GL-02 step 3. Sources: the LOCAL (never committed) compliance backlog rows EB-05, EB-18, EB-24, EB-27, EB-28, EB-29 and the matching matrix and dossier sections. Every claim below is tied to the code on this branch, not to those documents.

## Deliverables

| # | File | Item | In the repo? |
|---|---|---|---|
| 1 | `site/terms/index.html` | EB-05: the Terms of Use the paywall already links to (404 until now) | Yes |
| 2 | `site/privacy/index.html` | EB-28: PROPOSED text pack (rights, Do Not Track, subscription, retention) and two accuracy fixes | Yes (diff) |
| 3 | `site/.well-known/security.txt`, `site/security/index.html` | EB-27: RFC 9116 contact and a vulnerability-disclosure page | Yes |
| 4 | `scripts/go-live/find-placeholders.sh`, `scripts/ci/check_release.py` | `__SECURITY_EMAIL__` and `__GOVERNING_LAW__` tracked like `__SUPPORT_EMAIL__` | Yes |
| 5 | Incident-response plan draft; App Store Connect answers draft (EB-27, EB-29) | LOCAL only, in the compliance folder | **No** (by design) |
| 6 | This report; `build/logs/journal/2026-10-25-drafts1.md` | | Yes |

## 1. Terms of Use (`site/terms/index.html`)

**Apple's EULA, and which parts these Terms replace.** The draft keeps Apple's Standard EULA as the license (no custom EULA in App Store Connect) and says these Terms add to it. If they conflict, the Standard EULA controls, **except "Minors, parents and guardians" and "Governing law"**, which apply instead. Liability and warranty adopt the Standard EULA's own sections rather than drafting a second, conflicting cap (Apple's page, read 2026-10-25: sections "No Warranty", "Limitation of Liability" with a US$50 cap, "Governing Law" California and Santa Clara County).

| Section | Claims | Code facts |
|---|---|---|
| The short version | Independent app; Tally Annual renews yearly until cancelled; Apple handles payment, cancellation and refunds; own account only; Canvas is the official record | `L10n.swift:355` (disclaimer); `Products.storekit:108` (`P1Y`); `L10n+Subscription.swift:347-351` ("Apple handles payment, renewals and refunds") |
| About these terms | Covers the app and its subscription; provider = the App Store's seller | No entity name exists in the repo (counsel C1) |
| Apple's standard license | As above | `SubscriptionConfig.swift:40-43` (the `/terms` path, "Apple's standard EULA or Tally's own") |
| Subscriptions and the free trial | One-year subscription; price is the App Store's, shown before buying; the screen lists what's included; only at enabled schools | `PaywallView.swift:178-182` (`displayPrice`, the most prominent text); `PaywallModel.swift:134-152` (price text never reformatted); `PaywallView.swift:98-140` (features); `L10n+Subscription.swift:240-244` (works at enabled schools) |
| Free trial | 2-week free trial if eligible; the screen shows its end date; charged unless cancelled 24 hours before | `Products.storekit:95-98` (`P2W`, free); `PaywallModel.swift:84` (trial only when StoreKit offers one); `PaywallModel.swift:166-221`, `L10n+Subscription.swift:65-69,89-95` (end date and the 24-hour sentence) |
| Renewals | Renews yearly unless cancelled 24 hours before; Apple's price-change notice; reminders 40 and 20 days ahead while set to renew | `L10n+Subscription.swift:78-84` (`renewalAutoCancel`); `RenewalReminderPlan.swift:3-4,31` (`[40, 20]`, only while auto-renew is on, never a school seat); `L10n+Subscription.swift:448-454` (banner if notifications are off) |
| After you subscribe | Confirmation with plan, amount, renewal date and how to cancel, re-openable in Settings > Subscription; offer codes via Apple's sheet; no Family Sharing | `PurchaseConfirmationView.swift:17`; `SubscriptionSettingsView.swift:53-57`; `L10n+Subscription.swift:464-492`; `PaywallView.swift:65,248-253`; `Products.storekit:92` (`familyShareable: false`); `EntitlementPolicy.swift:10-24` (family-shared never entitles) |
| Without a subscription | Dashboard stays free; saved data shown, not refreshed | `L10n+Subscription.swift:365-381`; `SubscriptionConfig.swift:7-15` |
| School seats | The school holds the purchase | `L10n+Subscription.swift:299-303,353-357`; `EntitlementPolicy.swift:12-24,112-120` |
| Cancelling | Settings > your name > Subscriptions, or Manage Subscription; status shows "Active until"; deleting or Sign Out & Erase doesn't cancel | `L10n+Subscription.swift:81,287-291,329-333,456-460`; `SubscriptionSettingsView.swift:98-100`; `SettingsView.swift:122` (`manageSubscriptionsSheet`) |
| Refunds | Apple only; Request a Refund or reportaproblem.apple.com; school turned off: cancel or refund | `L10n+Subscription.swift:335-339` ("Tally cannot refund; Apple decides"), `:389-393`; `SubscriptionSettingsView.swift:101-105`; `site/support/index.html:12` |
| Using Tally | Reads from Canvas; never changes grades or coursework; What-If stays on the iPhone; acceptable-use list | `HTTPTransport.swift:3` (GET, POST, DELETE only); POST/DELETE only for the token (`TokenEndpoint.swift:46,52`) and Canvas's pairing flow (`LinkManagementUseCases.swift:80,114,145`); `WhatIfModel.swift:10-11,16` (never written, never saved) |
| Your information | No account, no server; data goes Canvas to iPhone; links the policy | `L10n.swift:1465`; `AppEnvironment.swift:88` (the only live destination is the school's Canvas: `check_policy_matches_app.py` PASS) |
| Minors, parents and guardians | Age range from Apple where rules apply; permission screen; Ask to Buy; **EB-05 minors clause** | `AgeAssurance.swift:147-149` (request points); `DeclaredAgeRangeAdapter.swift:49`; `L10n+AgeAssurance.swift:11,17`; `L10n+Subscription.swift:210-214` (Ask to Buy). The AGE-1 report left "no enforcement of terms against an unconsented minor" to this clause (`age1-report.md`, duty table) |
| Instructure and Canvas | The in-app disclaimer, verbatim (EB-16) | `L10n.swift:355` |
| Disclaimers | Canvas is the official record; saved data offline; calculated grades can differ; don't rely on reminders alone | `site/support/index.html:10` (saved data); `WhatIfModel.swift:13-14` (estimates); `InsightsConfig.swift:134-135` (quiet hours 23:00-07:00 move reminders); reminders need the notification permission (`L10n+Subscription.swift:448-454`) |
| Limitation of liability | Adopts the Standard EULA's section; non-waivable rights preserved | Apple's Standard EULA (see above) |
| Changes to these terms | Effective date and release notes; significant changes noticed to the store, parent re-consent | `docs/release/significant-change-checklist.md`; `SignificantChangeConsentAdapter.swift` (AGE-1, EB-02) |
| Governing law | `__GOVERNING_LAW__` | Tracked by the scanner (§4) |
| Contact | `__SUPPORT_EMAIL__`; links the Security page | `site/support/index.html:5` |

## 2. Privacy Policy: the EB-28 text pack (proposed diff to `site/privacy/index.html`)

| Change | What it says | Code facts |
|---|---|---|
| "Purchases" becomes "Purchases and subscriptions" (+3 sentences) | Renews yearly at the App Store's price; 2-week trial, charged unless cancelled 24 hours before; cancel path; links the Terms | As in §1 (EB-18 strings `L10n+Subscription.swift:78-95`) |
| New "Our website." paragraph | Static pages, no cookies, analytics, ads or scripts; host logs; **Do Not Track** | `site/` has no `<script>` tag (grep 2026-10-25); `PrivacyInfo.xcprivacy:5-8` (no tracking) |
| Summary-sharing sentence (accuracy fix) | A weekly plain-text summary via Send My Week; Hide Course Names shows counts only | `L10n+FeatB.swift:16-33`; `WeekShareText.swift:21-33`; `DashboardView.swift:636`. There is no monthly summary and no separate Mail button |
| New "How long Tally keeps it." paragraph (EB-28 retention) | Latest copy only, replaced on refresh; kept until erased or the app is deleted; shown without refresh after a lapse; only the subscription's end date in the Keychain | `SnapshotStore.swift:74-85` (seal and atomically replace on commit); `L10n+Subscription.swift:371-375`; `EntitlementRecord.swift:3-7` (never a receipt, transaction ID or price); `KeychainEntitlementStore.swift:52-60`; Sign Out & Erase deletes it (`AppModel.swift:699`) |
| "Deleting the app also deletes its data" replaced (accuracy fix, dossier P3) | Keychain can keep the sign-in and subscription date; reinstall removes the old sign-in; the EB-17 footer sentence | `LaunchBootstrapper.swift:60-63,204-209`; `L10n.swift:1277` |
| New "Your privacy rights" section | What we hold (nothing but what you send); see, delete, correct via school; how to ask; 45-day answer; appeal in 60 days; attorney general; no sale, sharing, targeted ads or profiling; no discrimination | No account or server (`AppEnvironment.swift:88`); no third-party code (`packages/TallyAppleKit/Package.swift:23`; `packages/TallyCore/Package.swift:22,30`) |

**Reconciled, not duplicated.** The EB-26 bullets (Erase Saved Data, the 30-day automatic erase; `SubscriptionConfig.swift:52`) and the age-signal paragraph (dossier P6) are already live and unchanged; the retention paragraph points to them ("as described below"). The 40/20-day reminder sentence stays in "Reminders and widgets".

**Kept as is.** The `POLICY-FLOWS` block is unchanged and accurate for the prose (no flow was added or removed). The effective date stays `__EFFECTIVE_DATE__` for the owner (GL-02). Both phrases `check_privacy_manifest.py` requires are untouched.

## 3. Security (EB-27)

- `site/.well-known/security.txt`: `Contact: mailto:__SECURITY_EMAIL__`, `Expires: 2027-10-24T23:59:59.000Z` (just under a year, per RFC 9116's recommendation), `Policy: https://tally-app.dev/security/`, `Preferred-Languages: en`, `Canonical`. `site/.nojekyll` already makes `/.well-known/` servable.
- `site/security/index.html`: how to report, scope (the app, widgets and `tally-app.dev`; not Canvas, Instructure or Apple), what to expect, testing in good faith. Code facts: Settings > About shows the version (`SettingsView.swift:518`); "Explore with Sample Data" (`L10n.swift:346`); no server (`AppEnvironment.swift:88`).

## 4. Placeholder registration

`find-placeholders.sh`'s "Tagged placeholder" pattern now also matches `__SECURITY_EMAIL__` and `__GOVERNING_LAW__`, so `check_release.py`'s `REL.go-live.owner-values` (PENDING, M5) lists them beside `__SUPPORT_EMAIL__`. The two go-live check titles now name the new pages. **Mutation check:** with the two names removed from the pattern, none of `site/terms/index.html:78`, `site/security/index.html:13`, `site/.well-known/security.txt:2` is listed; restored byte-identical (sha256 `cac64d72e7e71f52c423c9359987fba910d830b37fa950519d986449a95e6970` before and after), and all three are listed again.

## 5. Verification (local; the brief runs no CI)

| Command | Result |
|---|---|
| `python3 scripts/ci/check_policy_matches_app.py --self-test` | PASS, 10 of 10 |
| `python3 scripts/ci/check_policy_matches_app.py .` | PASS |
| `python3 scripts/ci/check_privacy_manifest.py` | PASS, 11 checks, 0 failed |
| `python3 scripts/ci/check_privacy_manifest.py --self-test` | 17 checks passed |
| `python3 scripts/ci/check_release.py --self-test` | 51 checks passed |
| `python3 scripts/ci/check_release.py --source .` | FAIL 0, PENDING 3, PASS 31 (same counts as on `d8ab0c3`); `REL.go-live.owner-values` and `REL.go-live.legal` list the new pages |
| `bash scripts/go-live/find-placeholders.sh` | 24 lines (11 tagged, 6 legal-draft markers), every new placeholder listed |
| Tag balance of the three pages (Python `html.parser`) | No unclosed or mismatched tags; no `<script>` |

UNVERIFIED: how the pages render in a browser (they reuse `/_style.css`'s existing classes only).

## 6. Counsel questions (each is also an HTML comment on its page)

Terms of Use:
- **C1.** Name the legal entity and postal address (Guideline 5.1.1(i); GL-02).
- **C2.** Keep Apple's Standard EULA with these as additional terms, or upload a custom EULA (then Apple's minimum terms apply)? Can additional terms replace the Standard EULA's California law and Santa Clara County courts? Does "claims come to us, not to Apple" match the developer's role as principal (DPLA Schedule 2 §1.3)?
- **C3.** Do the renewal sentences, with the paywall's disclosure, meet Cal. Bus. & Prof. Code 17601-17602 (including "the amount of the charge may change"), ROSCA (15 U.S.C. 8403), N.Y. GBL 527-a and Minn. Stat. 325G.56-.62? May the 40/20-day reminders be promised?
- **C4.** Is an Apple-only refund route enough under state law, including when a minor disaffirms a purchase?
- **C5.** Is the acceptable-use list enough beside the Standard EULA's restrictions, and does it fit Instructure's Canvas API Policy?
- **C6.** The minors clause: does it meet Tex. Bus. & Com. Code §121.056(a)(1), Utah Code §13-76-202(4)(a), La. R.S. 51:1773(D)(1) and Ala. HB 161 (2026) §9(c)(1)? Should it name the states? How does general minors' disaffirmance law apply to a subscription?
- **C7.** Is the "as is" disclaimer enforceable for consumers in every state, or does any state need a carve-out?
- **C8.** Is adopting the Standard EULA's US$50 cap appropriate for a subscription priced above it, and for minors?
- **C9.** Change notice: Tex. §121.053 and §121.022(g); do existing adult users need advance notice of a change?
- **C10.** Governing law, venue, and whether to add arbitration or a class-action waiver (none drafted), given minor users.

Privacy Policy:
- **C11.** May the policy carry the renewal terms by cross-reference to the Terms?
- **C12.** Does the Do Not Track sentence meet Cal. Bus. & Prof. Code 22575(b)? Do the final host's terms support "we don't receive or keep those records"?
- **C13.** Retention (Guideline 5.1.1(i); C.R.S. 6-1-1308.5(2)(a)(III)): is a saved copy that stays readable with no time limit after a subscription ends acceptable, when the 30-day limit covers only a school turning Tally off?
- **C14.** Rights paragraph: confirm the 45-day answer and 60-day appeal windows (engineering draft values, not re-read against Tex. Bus. & Com. Code ch. 541); whether a second request method is needed (541.055); whether App Store Connect data (sales reports; crash reports from users who opt in) must be mentioned; how long support e-mails may be kept.

Security page:
- **C15.** The good-faith safe-harbor sentence: wording and scope (Computer Fraud and Abuse Act; DMCA anti-circumvention), and that it cannot be read as authorizing access to a school's Canvas.

Owner-only (not counsel): the security page's 5-business-day acknowledgement and "no payment for reports" are commitments for the owner to make.

## 7. Owner approval

Every new public sentence, numbered, for line-by-line approval: **107 sentences** (Terms 64, Privacy 24, Security 19). "(reused)" marks wording the owner already approved elsewhere.

### Terms of Use (`site/terms/index.html`)
1. T1. DRAFT-PENDING-LEGAL-REVIEW. These terms have not yet been reviewed by counsel.
2. T2. Effective: `__EFFECTIVE_DATE__` · Applies to the Tally iPhone app
3. T3. Tally is an independent app that shows your own Canvas information on your iPhone.
4. T4. Tally Annual renews automatically every year until you cancel.
5. T5. Apple sells it and handles payment, cancellation and refunds.
6. T6. Use Tally only with your own Canvas account, and follow your school's rules.
7. T7. Your school's Canvas is the official record of your grades and due dates.
8. T8. These Terms of Use ("Terms") cover the Tally iPhone app and its subscription.
9. T9. By using Tally, you agree to them.
10. T10. Tally is provided by its developer, named as the seller on Tally's App Store page ("we" or "us").
11. T11. Tally is licensed to you under Apple's Licensed Application End User License Agreement (the "Standard EULA").
12. T12. These Terms add to it.
13. T13. If the two conflict, the Standard EULA controls, except for "Minors, parents and guardians" and "Governing law" below, which apply instead of anything in the Standard EULA that says otherwise.
14. T14. Questions and claims about Tally come to us, not to Apple.
15. T15. Tally Annual is a subscription that lasts one year and renews automatically every year until you cancel.
16. T16. Its price is the one the App Store shows on Tally's subscription screen before you buy.
17. T17. That screen also lists what the subscription includes.
18. T18. Tally works only at schools that have enabled it, so please check that yours has before you subscribe.
19. T19. Free trial. If your Apple Account is eligible, Tally Annual starts with a free 2-week trial, and the subscription screen shows the date it ends.
20. T20. Unless you cancel at least 24 hours before the trial ends, Apple then charges you the yearly price.
21. T21. Renewals. Unless you cancel at least 24 hours before your renewal date, Apple charges the yearly price again and your subscription continues for another year.
22. T22. If the price ever changes, Apple tells you before the new price applies, and asks for your agreement where its rules require it.
23. T23. While your subscription is set to renew, Tally reminds you on your iPhone 40 and 20 days before it renews, if you allow notifications.
24. T24. After you subscribe. Tally shows a confirmation with your plan, amount, renewal date and how to cancel, and you can open it again in Tally's Settings > Subscription.
25. T25. If you redeem an offer code, the terms Apple shows you when you redeem it apply.
26. T26. Tally's subscription can't be shared through Family Sharing.
27. T27. Without a subscription. Your Dashboard stays free, and Tally keeps showing the information it last saved but doesn't refresh it.
28. T28. School seats. If your school gives you Tally through Apple, your school holds that purchase, so questions about it go to your school.
29. T29. Apple manages your subscription, so you cancel it through Apple: on your iPhone, go to Settings > your name > Subscriptions, or tap Manage Subscription in Tally's Settings > Subscription.
30. T30. After you cancel, Tally's Settings > Subscription shows the date your subscription stays active until.
31. T31. Deleting Tally, or using Sign Out & Erase, doesn't cancel your subscription.
32. T32. Apple handles payments and refunds, and we can't issue refunds ourselves.
33. T33. To ask Apple for one, tap Request a Refund in Tally's Settings > Subscription, or visit reportaproblem.apple.com.
34. T34. Apple decides refund requests under its own policies.
35. T35. If your school turns Tally off while you're subscribed, Tally tells you, and you can then cancel or ask Apple for a refund.
36. T36. Tally shows your own Canvas information, using your own Canvas sign-in, at schools that have enabled it.
37. T37. It reads that information from Canvas: it doesn't change your grades or coursework there, and What-If scores stay on your iPhone.
38. T38. When you use Tally, please:
39. T39. use it only with your own Canvas account, or, as a parent or guardian, with your own Canvas observer account;
40. T40. follow your school's rules and Canvas's own terms;
41. T41. not try to see information you aren't allowed to see, or get around your school's settings;
42. T42. not interfere with Canvas, Tally or tally-app.dev, for example by overloading them, and not test them for security problems except as our Security page describes.
43. T43. There is no Tally account and no Tally server holding your data. (reused, policy)
44. T44. Your Canvas information goes from your school's Canvas to your iPhone, and isn't sent to us.
45. T45. Our Privacy Policy explains what Tally uses, where it goes, and how to delete it.
46. T46. Tally is used by students who may be under 18. (reused, policy)
47. T47. If you're under 18, or under the age of majority where you live, please read these Terms with a parent or guardian.
48. T48. Where Apple indicates that age rules apply, Tally asks Apple for your age range, and a parent or guardian may need to give permission through Apple before you can keep using Tally.
49. T49. A purchase can also need a parent's approval through Apple's Ask to Buy.
50. T50. **Where a state law requires a parent's or guardian's consent, we will not enforce these Terms or the Standard EULA against a minor who doesn't have that consent.** (EB-05 minors clause)
51. T51. Tally is an independent app and is not affiliated with, endorsed by, or sponsored by Instructure, Inc. (reused, in-app)
52. T52. Canvas is a trademark of Instructure, Inc. (reused, in-app)
53. T53. Your school and Instructure, not we, run Canvas and decide when it's available.
54. T54. Tally shows a copy of the information your school's Canvas provides, and your school's Canvas remains the official record.
55. T55. Tally may show saved information while Canvas is slow or you're offline, and the grades it calculates, such as What-If results and estimates, can differ from your school's.
56. T56. Reminders depend on your iPhone's notification settings and on what Canvas provides, so please don't rely on Tally alone for an important deadline.
57. T57. To the extent the law allows, Tally is provided "as is" and "as available", as the Standard EULA's "No Warranty" section says.
58. T58. To the extent the law allows, our liability to you is limited as the Standard EULA's "Limitation of Liability" section sets out.
59. T59. Nothing in these Terms limits a right you have under a law that can't be waived by contract, such as consumer-protection laws where you live.
60. T60. If we change these Terms, we'll update the effective date above and describe the change in the app's release notes.
61. T61. If a change is significant under the law, we'll tell the App Store before it takes effect, and a parent or guardian may be asked through Apple to approve it again.
62. T62. These Terms, the Standard EULA and any dispute about Tally are governed by the laws of `__GOVERNING_LAW__`, without regard to its conflict-of-laws rules.
63. T63. Questions about these Terms: `__SUPPORT_EMAIL__`.
64. T64. To report a security problem, see our Security page.

### Privacy Policy (`site/privacy/index.html`, new or changed sentences only)
65. P1. Tally Annual renews automatically every year until you cancel, at the price the App Store shows before you buy.
66. P2. If you're eligible, it starts with a free 2-week trial, and Apple charges you when the trial ends unless you cancel at least 24 hours before.
67. P3. You can cancel anytime in Settings > your name > Subscriptions, or with Manage Subscription in Tally's Settings; our Terms of Use have the details.
68. P4. tally-app.dev is a set of static pages, such as this policy and our Terms of Use.
69. P5. The pages don't set cookies or run analytics, ads or scripts.
70. P6. Like any website, our host may record your IP address and the address of the page you open; we don't receive or keep those records.
71. P7. Neither Tally nor our website tracks you across other companies' apps or websites, so we treat everyone the same whether or not their browser sends a Do Not Track signal.
72. P8. (replaces "…a weekly or monthly summary…") A student can also share a plain-text summary of their week with anyone they choose.
73. P9. (replaces "…taps Share or Mail…") Nothing is sent until the student taps Send My Week and picks who receives it.
74. P10. If Hide Course Names is on, the summary shows only how many items are due each day.
75. P11. Tally keeps only the latest copy of your Canvas information and replaces it each time it refreshes.
76. P12. That copy stays on your iPhone until you or Tally erase it, as described below, or you delete the app.
77. P13. If your subscription ends, Tally keeps showing the saved copy but stops refreshing it.
78. P14. To work offline, Tally also keeps the date your subscription is active until in your iPhone's Keychain; it never keeps a receipt, a payment detail or a price.
79. P15. (replaces "Deleting the app also deletes its data.") Deleting the app deletes Tally's files from your iPhone, but your iPhone's Keychain can keep Tally's Canvas sign-in and subscription date; reinstalling Tally removes the old sign-in.
80. P16. Before you delete Tally, use Sign Out & Erase to end its access at your school. (reused, in-app EB-17 footer)
81. P17. Because there is no Tally account or server, we hold no Canvas information about you.
82. P18. The only personal information we may have is what you send us yourself, such as a support e-mail.
83. P19. Your Canvas information is on your iPhone: you can see it in Tally and delete it with Sign Out & Erase, and to correct it, ask your school, because Tally copies it from Canvas.
84. P20. To ask what personal information we hold about you, or to have it corrected or deleted, e-mail `__SUPPORT_EMAIL__`.
85. P21. We'll answer within 45 days.
86. P22. If we decline your request, you can appeal by replying to our answer, and we'll answer your appeal in writing within 60 days, with our reasons.
87. P23. If you're still not satisfied, you can contact your state's attorney general.
88. P24. We don't sell or share personal information or use it for targeted advertising or profiling, and we won't treat you differently for using these rights.

### Security (`site/security/index.html`, `site/.well-known/security.txt`)
89. S1. DRAFT-PENDING-LEGAL-REVIEW. This page has not yet been reviewed by counsel.
90. S2. How to report a security problem in Tally
91. S3. E-mail: `__SECURITY_EMAIL__`
92. S4. If you think you've found a security problem in the Tally app or on tally-app.dev, please e-mail us.
93. S5. Tell us what you found, how to reproduce it, and the app version (Tally's Settings > About).
94. S6. Please don't send real grades, passwords, sign-in tokens or anyone's personal information.
95. S7. Your own test data, or Tally's Explore with Sample Data mode, is enough to show a problem.
96. S8. The Tally iPhone app and its widgets.
97. S9. The pages on tally-app.dev, including the page that finishes signing in.
98. S10. Your school's Canvas, Instructure's systems and Apple's App Store are run by others, so please report problems with them to your school, Instructure or Apple.
99. S11. We'll acknowledge your report within 5 business days and keep you updated until it's resolved.
100. S12. Please give us a reasonable time to fix a problem before you make it public, and we'll agree a date with you.
101. S13. Tally has no server and holds no student data, so most fixes reach people as an app update through the App Store.
102. S14. We don't offer payment for reports.
103. S15. Only test with your own Canvas account or with Explore with Sample Data, never with someone else's account or data.
104. S16. Don't do anything that could disrupt your school's Canvas or other people.
105. S17. If you follow this page in good faith, we won't take legal action against you for your research.
106. S18. Our security contact is also published at /.well-known/security.txt.
107. S19. (security.txt comment line) Tally's security contact (RFC 9116). Policy: how to report, and what to expect.

**Headings and labels to approve with them (not counted as sentences).** Page titles "Tally Terms of Use", "Tally Security". Terms headings: Terms of Use; The short version; About these terms; Apple's standard license; Subscriptions and the free trial; Cancelling; Refunds; Using Tally; Your information; Minors, parents and guardians; Instructure and Canvas; Disclaimers; Limitation of liability; Changes to these terms; Governing law; Contact; run-in labels Free trial., Renewals., After you subscribe., Without a subscription., School seats. Privacy: the label "Purchases." becomes "Purchases and subscriptions."; new labels "Our website.", "How long Tally keeps it."; new heading "Your privacy rights". Security headings: Security; Reporting a problem; What this page covers; What to expect; Testing in good faith. `security.txt` fields: Contact, `Expires: 2027-10-24T23:59:59.000Z`, Policy, Preferred-Languages `en`, Canonical. Navigation links on the two new pages.

## 8. Open items

1. **`check_policy_matches_app.py`'s summary-sharing detector is stale.** FEAT-B shipped a weekly summary share (`WeekShareText.swift`, `DashboardView.swift:636`), but the detector looks only for `SummaryShar*`/`WeeklySummary`/`MonthlySummary`, so it still reports "not wired" and the allowlist's "no such feature exists" note is wrong. The policy's `summary-sharing: active` is in fact accurate. Fix in the script (detector, allowlist entry, and the self-test's expected set), outside this package's lane.
2. Still in the live policy, not in this pack: "Finding your school" describes school search and the school-list download, neither wired (allowlisted, dossier P1); the parent section describes real-account linking (P14); the policy's disclaimer omits "sponsored by" (P11, EB-16); the change notice mentions only release notes (P7).
3. "Sign Out & Erase … deletes all Tally data" (live bullet): the age-check record (last request date, approved app version, the app's own rating) is not reset by sign-out (`AppModel.signOut`, `AgeAssuranceFileStores.swift`); it holds no age and the Children section describes it, but the owner may want "all your Tally data".
4. `docs/GO-LIVE.md` GL-02 should list the two new placeholders and the security mailbox to set up (docs, PMO lane; scripts already track them).
5. `security.txt` expires 2027-10-24: renew it at each yearly release review.
6. The store description has no Terms of Use link (Guideline 3.1.2): add `https://tally-app.dev/terms/` or keep App Store Connect's EULA on Apple's standard one and link that (owner).
7. This branch changes `site/privacy/index.html`, a `check_significant_change_notice.py` surface (the script is not wired into CI). Engineering view: "no" (no data, rating or monetization change; the text describes existing behaviour). The PMO adds the ledger row when it knows the merge commit.
8. Not done here: Spanish versions (EB-08); links to the Terms and Security pages from `/` and `/support/`; an in-browser rendering check (UNVERIFIED).
