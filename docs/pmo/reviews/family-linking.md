# Family Linking Review — Tally

Author: Family Linking Specialist (product, security, Canvas integration). Date: 2026-09-26. Branch `pmo/assessment` (local only; nothing committed).

**Owner request (verbatim):** *"One enhancement to ideate on is being able to link a parent account with their student(s). I am unsure of what existing capabilities such as that are allowed by canvas, but at a minimum would need to allow the student (actual canvas user) to 'invite' their parent(s) whom would have an encrypted view of their students data using the student credential. Both the parent and user would need to have profile options to manage linked accounts. Parental views would need to have some sort of header toggle to be able to switch between their linked students dashboards/data."*

**Inputs:** `docs/pmo/02-program-plan.md` (R3, R8, R10, R16, R18), `docs/adr/0001-canvas-sign-in-launch-handshake.md`, `docs/GO-LIVE.md` (GL-01, GL-05), `docs/BACKLOG.md` (BL-05), `docs/pmo/reviews/security.md`, `encryption.md`, `architecture.md` §3.2–3.5, `ux-ui.md` §3.4 and §3.7.7, `pricing-licensing.md`, `docs/pmo/ux/insights-at-a-glance.md` §1 and §3.6, `docs/go-to-market/school-admin-setup-guide.md`.

**Label convention:**
- **VERIFIED (docs)**: read on Instructure's, Apple's or the U.S. government's own page on 2026-09-26.
- **VERIFIED (OSS)**: read in Instructure's open-source code. `canvas-lms` master `1c9f0bb801` and `canvas-ios` `195fb97b21`, both last pushed 2026-04-30. Instructure-hosted Canvas may differ, so hosted behaviour is **UNVERIFIED** until WP FAM-01 tests it.
- **UNVERIFIED**: inferred, or not confirmed at a primary source.
- Nothing here is legal advice. The FERPA and App Review readings go to counsel under GL-03.

---

## 1. Executive summary

- **Canvas already has the parent model the owner is describing, natively.** It is called an **observer**.
  - A student creates a **pairing code**. The parent signs in with their **own** Canvas observer account and enters the code.
  - From then on the parent can read the student's courses, assignments, due dates and grades. The parent can never submit or act as the student.
  - A student can create the code through the API: `POST /api/v1/users/self/observer_pairing_codes`. Instructure's own iOS app does exactly this.
  - Evidence: VERIFIED (docs) for the flow, the endpoints and the scopes; VERIFIED (OSS) for the rules. Behaviour with Tally's third-party key on hosted Canvas is UNVERIFIED (FAM-01).
- **The one part of the idea we should not build is "using the student credential."** Handing a parent the student's password or Canvas token has four problems:
  - it lets the parent act as the student;
  - Instructure's docs treat tokens as password-equivalent;
  - it breaks ADR 0001 and R3, which keep tokens device-only;
  - with a PKCE public client it doesn't even work, because the refresh token rotates on every use, so two phones sharing one would keep signing each other out.

  The goal behind the idea still stands: the student decides, and the parent's view is private and encrypted. The observer design delivers that goal, and it keeps a copy of the student's data on nobody's device except the parent's own.
- **Recommended design.**
  - The student taps **Invite a parent**. Tally creates a Canvas pairing code and hands it to the share sheet, or shows it as a QR code in person.
  - The parent installs Tally, chooses **I'm a parent**, signs in with their own observer account and enters the code.
  - The parent gets a **header student-switcher** over a per-student dashboard.
  - Each student's data is stored in the parent's own sealed vault, keyed per student, and crypto-shredded on unlink.
  - There is no Tally server anywhere.
- **Two honest limits come from Canvas, not from Tally.**
  - (1) **Pairing codes only exist where the school has turned on self-registration.** Self-registration is off by default. Where it is off, the student sees no "Pair with Observer" button and the API refuses the request. VERIFIED (docs + OSS).
  - (2) **A student cannot remove an observer.** Only the observer or a school admin can. VERIFIED (OSS); no student UI is documented. So Tally's student screen can *show* who can see their data, but "revoke" means asking the school. For K-12 minors that is also legally correct, because parents hold FERPA rights until the student is 18 or in college.
- **Three rulings need a narrow change.**
  - **R16** (read-only): allow three user-initiated link-management calls. These are create code, add student by code, and parent unlink.
  - **R8** (single account): the rule stays one Canvas account, but that account can now hold many *students* (subjects). This is not BL-05's multi-account switcher.
  - **R10** (Lock Screen privacy) extends to parents' phones, with a "Hide student names" toggle.
- **Biggest risk: policy, not code.** A parent view overlaps Instructure's free Canvas Parent app, which raises the API Policy's "competitive purposes / mirror or replicate" exposure that GL-01 already carries.
  - Put family linking in the Instructure partner request before building.
  - Ship it after v1 (v1.1), gated on the FAM-01 real-Canvas spike.
- **Schools without observers:** v1.1 offers only a student-initiated, one-off **"Send an update"** share sheet. This is consistent with R18 and needs no hosting.
  - A live CloudKit share (`CKShare` + `encryptedValues`) is technically possible with no Tally server.
  - It is only truly end-to-end encrypted when Advanced Data Protection is on. It is only as fresh as the student's last refresh. It sits uneasily with the API Policy's "on behalf of any third-party" clause and with a school's deliberate choice to switch parents off.
  - **Backlog, not recommended now.**
- **Monetisation:**
  - Keep P3: Family Sharing **off** on the $9.99 student product.
  - When family linking ships, add a separate **"Tally Family"** subscription that the parent buys, with Family Sharing **on for that product only**. Irreversibility then applies to that product alone.
  - Apple's new **Group Purchases** (multiseat, "this winter") may later let a parent buy per-student seats instead.
  - This is an owner decision (F5).

## 2. Canvas capabilities (evidence)

### 2.1 The observer role

| Fact | Status |
|---|---|
| Canvas's Observer role is used to "link a user to a student". A link can be **account-level**, which auto-enrols the observer in the student's past, current and future courses, or **course-level**. One observer can link to many students. | VERIFIED (docs: *What is the Observer role?*, updated 2026-05-19) |
| Observers can view announcements, assignments, the calendar, modules, pages, the syllabus, and **grades, due dates and comments**. They **cannot submit** assignments or quizzes, comment on discussions, or view rosters. "Depending on the institution, observers can have different levels of access." | VERIFIED (docs, same page) |
| A linked observer is granted `read`, `read_as_parent` and `read_files` on the student user (`app/models/user.rb:1573-1574`). The course-level `ObserverEnrollment` grants `read` and `read_grades` on the student's enrollment (`app/models/enrollment.rb:1405-1406`). | VERIFIED (OSS) |
| `grade_permissions?` returns grades to an approved parent even when the course hides final grades from students (`lib/api/v1/user.rb:413-420`). **Tally must not show a parent more than the student sees**, so it respects `hide_final_grades` in parent mode (§6.2). | VERIFIED (OSS); hosted UNVERIFIED (FAM-01) |

### 2.2 Pairing codes

| Fact | Status |
|---|---|
| **What a code is:** six alphanumeric characters, case-sensitive. Valid for **seven days or first successful use**. One code links one observer to one student, so two parents need two codes. A student can have **five active codes**; creating a sixth deactivates the oldest. | VERIFIED (docs: *Pairing Codes – FAQ*, updated 2026-02-12) |
| **How Canvas makes it:** `SecureRandom.base64` stripped to 6 characters, `expires_at: 7.days.from_now` (`user.rb:3986-3993`). The pairing path calls `code.destroy` after a successful link (`user_observees_controller.rb:135-143`), so each code works once. The five-code cap is **not** visible in this method. | VERIFIED (OSS); five-code cap UNVERIFIED in source |
| **The API a student calls:** `POST /api/v1/users/:user_id/observer_pairing_codes`. It returns `{user_id, code, expires_at, workflow_state}`. Scope `url:POST\|/api/v1/users/:user_id/observer_pairing_codes`. | VERIFIED (docs: User Observees API; developerdocs portal) |
| **When Canvas refuses it:** the endpoint returns 401 **unless the user has a student enrollment *and* the root account has self-registration on** (`observer_pairing_codes_api_controller.rb:61`). Users may generate codes for themselves (`user.rb:1470-1494`). | VERIFIED (OSS) |
| **Instructure's own apps:** the Canvas Student iOS app calls `POST users/self/observer_pairing_codes` (`canvas-ios Core/…/APIPairingCode.swift:49`). The app shows the code plus a QR code with a share button. | VERIFIED (OSS + docs: *send a pairing code … iOS*, updated 2026-03-25) |
| **Where students can make codes:** only on the web and in the Canvas Student iOS app. The Parent app **cannot** generate codes. | VERIFIED (docs: FAQ) |
| **Who else can make codes:** instructors and admins, on the student's behalf, if the "Users – generate observer pairing codes for students" permission allows it. | VERIFIED (docs: FAQ) |

### 2.3 Parent self-registration

- **On the web:** the parent opens the school's Canvas URL, taps "Parents sign up here", and enters name, email, password and **one** pairing code. The banner appears only if the school enabled self-registration through Canvas authentication. VERIFIED (docs: *How do I sign up for a Canvas account as a parent?*, updated 2026-06-29).
- **In the Canvas Parent app:** the app does the same through an unauthenticated `POST /api/v1/accounts/:id/users` carrying the pairing code and `initial_enrollment_type: "observer"` (`canvas-ios APIPairingCode.swift:81-84`). VERIFIED (OSS).
  - **Tally should not copy this.** It would put a password in Tally's hands, which contradicts ADR 0001 ("Tally never sees or stores the school password").
- **Adding more students:** Account → Settings → **Observing** (`/profile/observees`, `config/routes.rb:1059`), or the Parent app's Manage Students. VERIFIED (docs + OSS).
- **Cross-school limit:** you "cannot add students whose accounts are not within your same institution". VERIFIED (docs: *link a student … as an observer*).

### 2.4 Who can list, add and remove links

| Action | Endpoint | Student (observee) | Observer (parent) | Evidence |
|---|---|---|---|---|
| List my observees | `GET /api/v1/users/self/observees` | n/a | **Yes.** Account-level links only; course-level links are not returned. | VERIFIED (docs); the `canvas-ios` comment "does not work with manually linked observees" |
| **List my observers** | `GET /api/v1/users/self/observers` | **Yes**: "all users are allowed to list their own observers" | n/a | VERIFIED (docs + OSS `user_observees_controller.rb:60-88`) |
| Add observee by code | `POST /api/v1/users/self/observees` with `pairing_code` | n/a | **Yes** | VERIFIED (docs + OSS `:125-182`) |
| Add observee with the student's **password or access token** | same endpoint, `observee[unique_id]`/`observee[password]` or `access_token` | n/a | Yes. Canvas allows it, but see §3. | VERIFIED (docs + OSS) |
| Add observee by id | `PUT …/observees/:id` | No | Admins only (`manage_user_observers`) | VERIFIED (OSS `:242-250`, `:364-370`) |
| **Remove a link** | `DELETE /api/v1/users/:observer_id/observees/:student_id` | **No.** `self_or_admin_permission_check` passes only when the caller *is the observer* or holds `manage_user_observers` (`:264-275`, `:313-317`). | **Yes** (own links) | VERIFIED (OSS); student web UI for removal not documented (UNVERIFIED) |
| Remove, on the web | Account → Settings → Observing → Remove | — | Yes | VERIFIED (docs) |

### 2.5 What an observer can read through the API

| Data | Request (observer's token) | Status |
|---|---|---|
| Courses, plus each observee's enrollment and scores | `GET /api/v1/courses?include[]=observed_users&include[]=total_scores…`. `observed_users` "will include data for observed users" (`courses_controller.rb:507-509`). The enrollment JSON embeds `observed_user` with that student's enrollments (`lib/api/v1/user.rb:345-346`). | **DISPUTED (PMO note 2026-09-26):** the Canvas data engineer reads the source as embedding `observed_user` only in the Enrollments API, with the Courses API appending the observee's own enrollment rows instead. The PMO could not settle this from `lib/api/v1/course.rb`. Resolve in FAM-01 against real Canvas and match `fixtures/canvas/personas/parent-observer`. Score fields for observers on hosted Canvas: UNVERIFIED (FAM-01). |
| One student's course list | `GET /api/v1/users/:observee_id/courses` needs "an observer of that user or an administrator" (`courses_controller.rb:669-670`) | VERIFIED (docs/OSS) |
| Assignment groups plus the student's submissions | `GET /api/v1/courses/:id/assignment_groups?include[]=assignments&include[]=submission&include[]=observed_users`: "submissions for observed users will also be included as an array" (`assignment_groups_controller.rb:112`). **One call serves every observee in that course.** | VERIFIED (OSS) |
| Assignments for one student | `GET /api/v1/users/:id/courses/:course_id/assignments` (`read_as_parent`, `assignments_api_controller.rb:1825-1834`) | VERIFIED (OSS) |
| Planner | `GET /api/v1/planner/items?observed_user_id=:id&context_codes[]=…`. `context_codes` is required, and courses are filtered to ones the caller observes (`planner_controller.rb:64-67, 182-199`). | VERIFIED (OSS) |
| Calendar | `GET /api/v1/users/:id/calendar_events` for "an observer of that user" (`calendar_events_api_controller.rb:376-380, 2089-2101`) | VERIFIED (OSS) |
| Canvas's own parent alerts | `GET/POST …/observer_alerts`, `…/observer_alert_thresholds` (`routes.rb:1886-1897`) | VERIFIED (OSS). **Not used** (§6.1). |
| Per-student **due-date overrides** in parent views | Planner with `observed_user_id` or the per-user assignments endpoint should return the student's effective dates. | UNVERIFIED (FAM-01) |

### 2.6 Institution settings that switch this off

- **Self-registration.**
  - It is set on the Canvas authentication provider as **None / Observer accounts only / All account types**, and it is **disabled by default**. VERIFIED (docs: *configure Canvas authentication*, updated 2026-09-11).
  - In code, `self_registration=` maps `none` to `jit_provisioning = false` (`authentication_provider/canvas.rb:43-61`), and `Account#self_registration?` reads `jit_provisioning?`. VERIFIED (OSS).
  - **Off means no pairing codes and no parent sign-up.** VERIFIED (docs FAQ: "only available … at institutions that have enabled self-registration").
- **SIS-provisioned observers.** Many K-12 districts create and link parent accounts themselves. Parents then exist even with self-registration off. VERIFIED (docs: "if an institution created an observer account linked to a student for you"). How common this is: UNVERIFIED.
- **Canvas Parent app access** "is controlled by the student's institution". VERIFIED (docs). This concerns Instructure's first-party mobile key, not Tally's key. But it signals the school's intent, and Tally should respect it (§4.4).
- **Observer role permissions** are institution-configurable ("different levels of access"). VERIFIED (docs).
- **Higher education.** We found **no data** on how many universities enable self-registration or observers. Self-registration is off by default, and FERPA moves rights to the student at college. **Assume most postsecondary schools won't support it until the pilot school says otherwise.** UNVERIFIED.

### 2.7 Canvas Parent app (for comparison only)

- It uses the same primitives: pairing codes (typed, or scanned as a QR code made by the Student app), a **Student Selector** to switch students, Manage Students, per-student alert thresholds, and course and calendar views. VERIFIED (docs: Parent iOS guides, updated 2026-02 to 2026-05).
- Instructure's apps get their client credentials from an undocumented first-party endpoint. Security §3.1 already rules that endpoint out for Tally as impersonation. Tally uses **its own** developer key (GL-01).
- The Student Selector is the precedent for the owner's header toggle (§7.1).

### 2.8 Scopes

The scope format is `url:<VERB>|<path>`. Each string below is from the endpoint's doc page or its route (`routes.rb:1286, 1396, 1847-1854, 1900-1901, 2091`). Scopes and endpoints are VERIFIED (docs/OSS). That these strings are selectable in every school's scope picker is UNVERIFIED. The full additive list is in §6.1.

### 2.9 Legal and policy framing

**FERPA** (20 U.S.C. §1232g; 34 CFR Part 99). Status: VERIFIED (docs: studentprivacy.ed.gov; eCFR current to 2026-09-09). The interpretation below is UNVERIFIED and goes to counsel (GL-03).

| Point | Source |
|---|---|
| Parents hold FERPA rights. "When a student turns 18 years old, or enters a postsecondary institution at any age," the rights transfer to the student, who becomes the "eligible student". | studentprivacy.ed.gov; 34 CFR 99.3, 99.5(a)(1) |
| An institution needs **signed, dated written consent** before disclosing, with exceptions. For an eligible student, one exception lets the institution disclose to parents of a **tax-dependent** student (99.31(a)(8)). The exceptions *permit* disclosure; they don't require it (99.31(d)). | 34 CFR 99.30, 99.31 |
| **What this means for Tally (interpretation, UNVERIFIED):** FERPA binds the institution. Under the recommended design the disclosure is made by the **school's Canvas**, under the school's own observer configuration. Tally never moves the student's data. **K-12 (<18):** the parent's access right doesn't depend on the student, so a student invite is a convenience and the student must not be told they can cut a parent off. **Eligible students:** the student-created pairing code is the student's affirmative act. That is why student-initiated linking matters, and why Tally must never let a parent start the link alone. | analysis |

**Apple App Review Guidelines** (last updated 2026-06-08). Status: VERIFIED (docs).

| Guideline | What it says (short) | Effect |
|---|---|---|
| 5.1.1(i) | The privacy policy must say what is collected and "how a user can revoke consent" | The policy gains a "Parents and observers" section: who sees what, and how to unlink. |
| 5.1.1(ii) | Provide an "easily accessible … way to withdraw consent" | Parent unlink is in-app. The student's path is honest: the school (§4.2). |
| 5.1.1(viii) | Apps may not compile personal information "without the user's explicit consent" | Parent mode shows a *different* person's data. The basis is the student's code (eligible students) or the school's parent relationship (K-12); Canvas Parent is the precedent. Say this in the review notes. Interpretation UNVERIFIED. |
| 5.1.2(i) | May not "use, transmit, or share someone's personal data without first obtaining their permission" | Recommended design: Tally transmits nothing, since Canvas serves the parent directly. Fallback designs (§5) *do* transmit, so they need the student's explicit, revocable, per-share permission. |
| 5.1.2(ii) | Data collected for one purpose may not be repurposed without further consent | The student's own cache is never repurposed into a parent view. The fallback requires a fresh, explicit share action. |

**Instructure API Policy** (effective 2025-08-12). Status: VERIFIED (docs).
- **§3 Restrictions** bars "use of or access to our APIs for competitive purposes".
  - The parent view overlaps the Canvas Parent app, so the GL-01 permission request must name it.
- **§2A "Don't impersonate"** says the application "should not mirror or replicate Instructure, our products". The same point applies.
- **§2B "Don't surprise"**:
  - lists "Use the APIs on behalf of any third-party". A parent using a student's token would be exactly that (§3). The CloudKit relay (§5) is arguably that.
  - requires the app to "outline what actions your application will take on the … User's behalf" at registration. The three link-management writes must appear in the school-admin guide and the partner request.
- **§2C "Be transparent"**: "clearly notify Users about what information will be disclosed" and "do not facilitate … publishing of private or confidential information". The invite sheet (§7.4) lists exactly what the parent will see.
- **§2D** requires actual notice before data practices become more permissive, with the ability to decline.
  - Adding family linking is such a change for existing users.
  - Ship it opt-in, with a one-time notice.
- **Rate limits:** Instructure "may revoke" tokens of apps using "a disproportionately large number of high-impact (e.g. non-GET) requests". The three writes are rare and user-initiated, with a client throttle (FAM-06).

## 3. Evaluation of the owner's proposal

The idea has three parts. Two are exactly right, and Canvas supports them natively:
- **the student invites**;
- **both sides manage links**.

It also has a third part, **"an encrypted view … using the student credential"**. Its goal is right: the parent's view should be private, and the student should stay in control. The mechanism is the one thing we recommend against, for these reasons:

1. **It lets the parent act as the student.**
   - The school credential usually unlocks much more than Canvas: email, registration and sometimes financial aid.
   - With it, the parent could submit work, message instructors or drop a course as the student, and Canvas's audit trail would attribute all of it to the student.
   - Canvas's observer role exists precisely so a parent can see without being able to act.
2. **Instructure treats tokens as passwords.** "Access tokens are password equivalent" (Instructure OAuth docs, VERIFIED in `security.md` §7).
   - Instructure already calls it a policy violation to ask another user to hand over a token.
   - A parent running on the student's token is also the API Policy's "on behalf of any third-party".
   - A Tally token is read-only only where the school enforces scopes; elsewhere it is full-power. The password is always full-power.
3. **It breaks our own security model.**
   - R3 and ADR 0001 keep the token in a `ThisDeviceOnly`, non-synchronizable Keychain item, so it never leaves the student's phone.
   - Sharing it means building a way to export a credential. That is the most dangerous code an app like this could contain.
4. **With our sign-in model it doesn't work.**
   - Canvas public (PKCE) clients **rotate the refresh token on every refresh** (SEC-02, VERIFIED (OSS)).
   - Two phones holding the same token pair would invalidate each other on every refresh, forcing repeated sign-ins.

**The compliant alternative gives the owner everything they asked for:**
- **Student-initiated invite:** a Canvas pairing code, created in Tally, shared by the student.
- **Encrypted view:** the parent's own phone fetches from Canvas over TLS and seals each student's data in its own AES-GCM vault with device-only keys (R3, TallyVault). No Tally server, no Apple server and no student device holds a copy for the parent.
- **The parent's own credential:** the parent signs in to Tally with their own Canvas observer account, through the same ADR 0001 handshake.
- **Profile options on both sides:** see §7.2 and §7.3. The one asymmetry comes from Canvas: a student can *see* who observes them but cannot remove an observer.
- **Header toggle between students:** a toolbar student-switcher (§7.1).

One variant of "use the student credential" is technically sound: the **student's device** fetches and relays an encrypted copy to the parent, so the credential never leaves the student's phone. That is the §5 fallback. It is second-best because the data is only as fresh as the student's last refresh, and because of its policy position.

## 4. Recommended design

### 4.1 Shape

```
 STUDENT'S iPHONE (Tally, student mode)                  PARENT'S iPHONE (Tally, parent mode)
 ─────────────────────────────────────                   ─────────────────────────────────────
 Settings ▸ Family ▸ Invite a parent                      Onboarding ▸ "I'm a parent" ▸ School
   │ POST /users/self/observer_pairing_codes               │ ASWebAuthenticationSession
   │   (student's own token; scope W1)                     │   canvas_login=1, force_login=1
   ▼                                                       │   parent's OWN Canvas observer login
 Code "X7Q2KP" · expires Fri · one use                     ▼
   │ share sheet / QR (in person)  ───────────────────▶  Enter code ▸ POST /users/self/observees
   │ (no Tally server; code never in a URL)                │   (pairing_code in body; scope W2)
   ▼                                                       ▼
 "Who can see my Canvas" = GET /users/self/observers     Canvas ── TLS ──▶ per-student sealed vaults
 New-observer alert on every refresh                     Header switcher: Maya ▾ | Leo
                                                         Unlink ▸ DELETE /users/self/observees/:id
```

The student does not need to keep using Tally for the parent view to work, and a school-linked parent (K-12 SIS) can use parent mode with no invite at all.

### 4.2 Student side

- **Invite a parent** (§7.4).
  - Tally calls `POST /api/v1/users/self/observer_pairing_codes` (proposed R16a) and shows the code, the expiry and a QR code, plus **Share…**.
  - If the school's key lacks the scope, or the student prefers it, **Get a code in Canvas** opens `https://<host>/profile/settings` in Safari instead. That page has Canvas's own "Pair with Observer" button. It is also the R16-strict route.
- **Who can see my Canvas** (§7.2).
  - The list comes from `GET /api/v1/users/self/observers?include[]=avatar_url`.
  - It shows everyone linked **at the account level**, whether they were linked through Tally, the Canvas web or by the school.
  - Course-level observers aren't returned by that call. The screen says so in one line.
- **Pending invites.** Canvas has no student API to list or cancel codes.
  - Tally keeps a local record of codes it created on this phone: an optional label the student typed, the creation time and the expiry. The code itself is kept in the Keychain (`WhenUnlockedThisDeviceOnly`) only until it expires, so the student can re-share it.
  - A code **can't be cancelled**; it dies after 7 days or on first use. The screen says so plainly.
- **Revoking.**
  - Canvas does not let a student remove an observer (§2.4). The observer row therefore offers **How to remove** instead of a destructive button.
  - It explains that only the school can remove the link, and gives a **Copy request** action. The request text is ready to paste to school support; Tally doesn't know the school's help-desk address.
  - For K-12 minors this is also the legally correct posture (§2.9).
- **New-observer alert (security control).**
  - On each refresh Tally compares the observer set with the last one it saw.
  - When a new observer appears, the student gets an in-app "Needs attention" alert, plus an optional notification (default on): "A new observer was linked to your Canvas account. Review in Tally."
  - This catches a leaked code or a link the student didn't expect.
  - The first refresh after sign-in only seeds the set, so it never fires then.
- **Sign Out & Erase** gains one line: "Signing out of Tally doesn't unlink parents. They can still see your Canvas."

### 4.3 Parent side

- **Onboarding:** "I'm a student" / **"I'm a parent or guardian"**, then the same institution picker (registry, §6.8).
- **Sign-in:** ADR 0001's PKCE handshake, plus two changes:
  - `canvas_login=1` sends the parent to Canvas's own login page, where parent accounts live, instead of the school's student SSO. The OAuth authorize endpoint forwards `canvas_login` and `authentication_provider` to the login page (`oauth2_provider_controller.rb:108-117`, `login_controller.rb:55`). VERIFIED (OSS); undocumented, so hosted UNVERIFIED (FAM-01).
  - `force_login=1` always, because family devices are often shared. A child's Safari session must never silently authorise the parent's sign-in.
- **Role check after sign-in.** Tally reads `GET /users/self/observees` and the user's enrollments. The results:
  - observees and no student enrolments → **parent mode**;
  - student enrolments and no observees → "This looks like a student account" with **Switch to student mode**;
  - both → parent mode with a **Me** entry in the switcher (§6.2).
- **No parent account yet.**
  - **Create a parent account** opens the school's Canvas sign-up page ("Parents sign up here") inside the same `ASWebAuthenticationSession`. The parent enters the code there. Tally never sees the password.
  - Whether Canvas then continues the OAuth flow automatically is UNVERIFIED (FAM-01). If it doesn't, the parent returns to Tally and taps **Sign in**.
- **Add a student:** type or paste the 6-character code, or scan the student's QR code. Tally calls `POST /api/v1/users/self/observees` with `pairing_code` in the **form body**. Instructure's own app puts it in the query string; the body keeps a live bearer secret out of URL logs.
- **Switch students:** the header switcher (§7.1).
- **Stop seeing a student.** Two distinct actions, each with its own copy (§7.7):
  - **Remove from Tally** is local. It purges that student's vault, notifications and widget configuration, and leaves the Canvas link intact. Use it when a family wants the parent in Canvas but not in Tally.
  - **Unlink in Canvas** calls `DELETE /api/v1/users/self/observees/:id`, then does the same local purge. It affects the Canvas Parent app and the web too.
- **Link disappears on its own** (student asked the school, school removed it, or school disabled observers): at the next successful refresh Tally purges that student's data. A parent must never keep data Canvas no longer lets them see. The parent gets one in-app notice.

### 4.4 When the school disables observers

The **signed institution registry** (security §3.2.1) gains a `family` block that the school admin sets up with the key (§6.8). Tally never guesses the school's intent from an error when the registry can tell it.

| School configuration | Student sees | Parent sees |
|---|---|---|
| Self-registration **Observer** or **All**, family scopes granted | Full invite flow | Full parent mode |
| Self-registration **None**, parents provisioned by the school (SIS) | "Your school links parents to students itself." No invite. **Who can see my Canvas** still works. | Parent mode works (they already have an observer account) |
| Self-registration **None**, no observers at all (likely common in higher ed; UNVERIFIED) | "<School> hasn't turned on parent accounts in Canvas." Offer **Send an update…** (§5.1). | School picker shows "Parent accounts aren't available at <School>". Stop. |
| Family scopes not granted on Tally's key (`401` with no `WWW-Authenticate`, per security §3.2) | **Get a code in Canvas** fallback (Safari) | "Your school's Tally setup doesn't include parent access." Offer **Request it** (the GL-01 "Ask my school" flow). |
| School turns observers off later, or revokes the key | Observer list empties. No alarm. | The subject is purged at the next refresh, with one notice: "<School> turned off parent access." |
| School blocks the Canvas Parent app but keeps observers | Registry flag `respectParentAppBlock` (default **true**) hides parent mode. Tally follows the school's evident intent even though its key is technically unaffected. | Same as the "no observers" row |

### 4.5 R8 (single account) vs BL-05 (multi-account)

| | R8 today | R8 as amended (**R8a**) | BL-05 multi-account |
|---|---|---|---|
| Canvas credentials in Tally | 1 | **1** (the parent's) | many (dual enrolment, two schools) |
| Data subjects | 1 (me) | **1 + N observees** | 1 per account |
| Switching | — | Changes the *subject*: no re-auth, same token, same school | Changes the *credential*: different token, host and 2-h window |
| Storage key | `accountKey` | `accountKey` + `subjectKey` (§6.3) | `accountKey` |
| Family with children at **two schools** | — | Not covered: needs two observer accounts | This is where BL-05 is needed. A parent switcher that spans schools = R8a + BL-05. |

R8a keeps R8's rule of "one active Canvas account" and its "no migration" promise. The `.me` subject maps onto today's paths (§6.3).

### 4.6 Rulings affected (proposed wording; the owner may veto)

- **R16a:** Tally never writes academic data to Canvas. The only permitted writes are three **link-management** calls, each started by an explicit tap:
  - create a pairing code (student);
  - add a student by code (parent);
  - unlink a student (parent).
- **R8a:** one active Canvas account per install. An observer account may hold several **subjects**, and all storage is keyed by account and subject.
- **R10a:** R10 applies unchanged to parents' devices, plus a "Hide student names" toggle. A parent's default notification set is smaller (§6.5).

## 5. Fallback option

### 5.1 v1.1 fallback: "Send an update…" (recommended)

- A student at a school without observers can send a **one-off** summary through the share sheet. The summary is built from the local snapshot:
  - "This week: 4 due, 1 missing (still open until Fri)";
  - the next 3 items;
  - grades **only if** the student switches on "Include grades" in the sheet.
- Consistency with existing rulings: it is the same no-hosting pattern as R18 and `insights-at-a-glance.md` §4 ("Send my week…").
- Privacy and policy: nothing persists and nothing needs revoking. The student sees the exact text before sending, which meets API Policy §2C ("clearly notify Users about what information will be disclosed") and 5.1.2(i).
- Cost: small, and reuses the digest builder.

### 5.2 Evaluated, not recommended now: student-controlled live share via CloudKit

**Mechanism** (no Tally server):
- The student's Tally writes a **read-only projection** of their data into a custom zone in the student's **private** CloudKit database. The projection follows the widget allowlist (encryption §3.3): due items, course codes and, opt-in, standings. It never includes instructor names, comments or tokens.
- Fields use `CKRecord.encryptedValues`.
- The student shares the zone with a `CKShare`: participant permission `.readOnly`, `publicPermission = .none`, invitation through `UICloudSharingController`, and the `CKSharingSupported` Info.plist key.
- The parent's Tally reads the shared database.
- Revocation: the student removes the participant or deletes the share. The parent's app deletes its copy when the share disappears.
- Status: VERIFIED (docs: CKShare, encryptedValues).

| Criterion | Assessment |
|---|---|
| **Encryption** | CloudKit encrypts `encryptedValues` on the device. The keys are **exclusive to the owner and share participants only when Advanced Data Protection is on**. Under standard data protection, Apple holds the keys. VERIFIED (Apple docs + iCloud data security overview, 2026-01-05). A true end-to-end promise for every family would need Tally's own HPKE layer, with a key exchanged in person by QR. That adds complexity and a key-verification UX. |
| **Freshness** | Only as fresh as the **student's** last successful Canvas refresh. Under ADR 0001's ~2-h window that is often hours or days. The parent can't refresh it. |
| **Student control** | Strong: the student starts it, can revoke it instantly for future updates, and chooses the scope. |
| **Instructure API Policy** | Weak. Tally would be retrieving Canvas data with the student's token in order to deliver it to a third party. That sits close to "on behalf of any third-party" and needs §2C disclosure. Where a school **deliberately** disabled observers, a Tally feature that recreates parent access looks like circumvention. It could put the per-school key (GL-01 route b) at risk. |
| **FERPA** | A student sharing their own records is not a disclosure by the institution. UNVERIFIED legal reading; counsel. |
| **Apple** | Allowed with explicit, revocable, student-initiated permission (5.1.2(i)); 5.1.2(ii) needs a fresh consent step. The privacy label is still likely "Data Not Collected", because Apple says developers aren't responsible for data Apple collects through CloudKit. But the compliance lane's R3 condition (a), "data flows only between the device and the institution's Canvas", would no longer hold. The label and privacy policy need re-analysis. UNVERIFIED. |
| **Cost** | CloudKit container and entitlements, a share-management UI on both sides, participant-removal handling, iCloud-signed-out states, and Apple Account requirements for both people. About the size of FAM-09 + FAM-10 again. |

**Recommendation: backlog (BL-F1), not v1.1.** Revisit only if Instructure confirms in writing that it is acceptable **and** pilot data shows real demand at schools without observers. Until then, "Send an update…" covers the need with none of the risk.

## 6. Architecture & security impact

### 6.1 Endpoints and scopes to add

Existing endpoints are reused with `include[]=observed_users`. **"Allow Include Parameters"** must stay on in the key (security §3.2.11).

| # | Role | Purpose | Request | Scope | New? |
|---|---|---|---|---|---|
| S1 | student | Who can see me | `GET /api/v1/users/self/observers?include[]=avatar_url&per_page=100` | `url:GET\|/api/v1/users/:user_id/observers` | **new, read** |
| W1 | student | Create invite code | `POST /api/v1/users/self/observer_pairing_codes` | `url:POST\|/api/v1/users/:user_id/observer_pairing_codes` | **new, write (R16a)** |
| O1 | parent | Linked students | `GET /api/v1/users/self/observees?include[]=avatar_url&per_page=100` | `url:GET\|/api/v1/users/:user_id/observees` | **new, read** |
| O2 | parent | Course-level links (the Parent app's method) | `GET /api/v1/users/self/enrollments?type[]=ObserverEnrollment&include[]=observed_users&include[]=avatar_url` | `url:GET\|/api/v1/users/:user_id/enrollments` | **new, read** (optional) |
| O3 | parent | Courses plus every observee's scores | `GET /api/v1/courses?enrollment_state=active&include[]=observed_users&include[]=total_scores&include[]=current_grading_period_scores&include[]=term&per_page=100` | `url:GET\|/api/v1/courses` | existing |
| O4 | parent | Groups, assignments, submissions (all observees in one call) | `…/assignment_groups?include[]=assignments&include[]=submission&include[]=observed_users` | existing | existing |
| O5 | parent | Planner per observee | `GET /api/v1/planner/items?observed_user_id=:id&context_codes[]=…` | existing | existing |
| O6 | parent | Calendar per observee | `GET /api/v1/users/:id/calendar_events?type=event&…` | `url:GET\|/api/v1/users/:user_id/calendar_events` | **new, read** |
| O7 | parent | Announcements, grading periods, colours | as today, with the observee's course context codes | existing | existing |
| W2 | parent | Add a student by code | `POST /api/v1/users/self/observees` (form body `pairing_code=`) | `url:POST\|/api/v1/users/:user_id/observees` | **new, write (R16a)** |
| W3 | parent | Unlink in Canvas | `DELETE /api/v1/users/self/observees/:observee_id` | `url:DELETE\|/api/v1/users/:user_id/observees/:observee_id` | **new, write (R16a)** |

- **Not used:** Canvas `observer_alerts` / `observer_alert_thresholds`.
  - Thresholds are writes that change Canvas's own notifications.
  - Using them would replicate Canvas Parent's alert feature.
  - Tally's local alert pipeline (R13) already computes alerts per subject.
- **Also not used:** add-observee by student password or token (§3).
- **Request cost:**
  - One O3 call covers every observee.
  - O4 is one call per course, shared by siblings in the same course.
  - O5 and O6 are per observee.
  - Two children with 6 courses each come to roughly 1 + 12 + 2×(2+1) + announcements ≈ **20–26 requests**, versus 13–19 for one student (architecture §3.3). The estimate is UNVERIFIED; FAM-04 measures it.

### 6.2 Domain model (TallyCore)

```swift
public enum Capability: Sendable { case ownCoursework, observes }        // derived after sign-in, never stored as truth
public struct Subject: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case me, observee(canvasUserID: String) }
    public let id: SubjectKey          // hex SHA-256(host|accountUserID|subjectUserID), truncated; no names
    public let kind: Kind
}
public struct AccountRole: Sendable { let capabilities: Set<Capability>; let subjects: [Subject] }  // subjects[0] == .me iff ownCoursework
```

- **Detection** is a pure function of O1, O2 and the courses call. It is covered by fixtures for student-only, parent-only, both, and a parent with zero observees.
- **`activeSubject`** is app-wide state injected into every tab (R1: `@Observable`, constructor injection, no singletons). It is persisted in `user-state` as an opaque `SubjectKey`, which fits ENC D-E4's "opaque IDs only" rule.
- **`CanvasSnapshot` gains `subject: SubjectKey`.** The grade engine is unchanged; in parent mode it runs on the observee's enrollment and submissions.
- **Parity rule**, enforced in the snapshot builder with a unit test: parent mode never renders a value the student's own view would hide.
  - It respects `hide_final_grades` (the OSS returns grades to parents regardless, §2.1).
  - It respects unposted scores and muted assignments.
- **Parent-mode feature set:**
  - **Kept:** Dashboard, Courses, Calendar, To-Do (read-only), Insights, what-if (local), week-ahead.
  - **Hidden:** "Mark done" (R16; it's the student's list), "Open in Canvas" deep links to student-only pages, and ICS subscription. The ICS feed is the *parent's* own calendar feed, and its contents for observers are UNVERIFIED.

### 6.3 Storage and encryption (with the Encryption lane)

```
accounts/<accountKey>/snapshot.v1.sealed                       # .me subject — unchanged path, no migration
accounts/<accountKey>/glance.v1.sealed                         # .me
accounts/<accountKey>/subjects/<subjectKey>/snapshot.v1.sealed # each observee
accounts/<accountKey>/subjects/<subjectKey>/glance.v1.sealed   # each observee (widget audience)
accounts/<accountKey>/user-state                               # per-subject rules keyed by opaque subjectKey
accounts.json                                                  # + capabilities, + subjectKeys[]  (NO names — ENC rule)
```

- **Keyring scope** grows from `(accountKey, audience)` to `(accountKey, subjectKey, audience)`. The `.me` subject uses today's key names, so nothing re-keys.
- **`VaultPurger.purge(subject:)`** shreds that subject's app and widget keys **before** deleting its directory, in the same order and with the same tests as §3.7 of the encryption review.
- **Sign Out & Erase on a parent account** purges every subject.
- **Observee names** live only inside sealed files. The switcher and widget read them from the per-subject glance, which is sealed with the widget key. `accounts.json` and file paths carry no names.
- **Protection classes are unchanged** (R3): CUFA files, `AfterFirstUnlockThisDeviceOnly` keys, backup excluded.
- **Pending-invite codes (student):** Keychain, `WhenUnlockedThisDeviceOnly`, deleted at `expires_at`. They are never in `user-state`, logs, notifications or URLs.

### 6.4 Refresh

- **Token behaviour:** one token per parent account. ADR 0001's 2-h window, reconnect and single-flight refresh apply unchanged.
- **Order of refresh:**
  1. The **active subject** is refreshed first, inside the existing 10-s UI budget.
  2. The other subjects follow, within the per-account `RequestScheduler` limit (≤3 in flight).
  3. Background runs rotate through subjects, bounded by the configurable `maxSubjectsPerBackgroundRun` (default 2).
- **Freshness footer** is per subject ("Maya · updated 2:14 PM").
- **Partial failure:** one subject failing (e.g. a course-level 401) does not fail the others.
- **Link disappearance** in O1/O2 triggers `purge(subject:)` after **two** consecutive successful refreshes. Two refreshes means one transient empty response can't erase data.

### 6.5 Notifications for parents (R10a)

| Kind | Parent default | Title / body (example) | Never |
|---|---|---|---|
| Week ahead (Sun 18:00) | **On** | "Maya's week" / "5 due · busiest Thu" | grades |
| Missing, still open | **On** | "Maya · Problem Set 6" / "Still accepted until Fri 11:59 PM." | points lost |
| New grade posted | Off | "Maya · New grade posted" / "Calculus II" | score |
| Below goal | Off (the parent must set a goal) | "Maya · Calculus II needs attention" / "Open Tally to see details." | score, goal value |
| 24 h / 1 h due reminders | **Off** (the student's own reminders do this) | as `insights-at-a-glance.md` §3.6 | grades |
| Sentinel (no refresh for 24 h) | On | "Tally hasn't refreshed since Tue" | — |

- **Hide student names** (default off): replaces the name with "Your student".
- **Hide course names** (existing) still applies.
- **Thread and identifier scheme:** `threadIdentifier = subjectKey`. IDs take the form `tally.<accountKey>.<subjectKey>.<kind>.<canvasID>.<ruleID>.<offset>`.
- **64-slot cap:** the budget planner splits the iOS cap across subjects, weighted by due-item count, with a floor of 4 per subject.
- **Student side:** the "New observer linked" notification carries no names: "A new observer was linked to your Canvas account."

### 6.6 Widgets and App Intents

- **Widgets:**
  - Parent widgets use `AppIntentConfiguration` with a `StudentEntity` parameter. The default is "Last viewed".
  - The entity query reads names from the per-subject glance only.
  - Every R10 and ENC D-E3 rule carries over: grades opt-in, `.privacySensitive()`, redacted when locked.
  - Lock Screen accessories show initials only: "M · 2 due".
- **App Intents:**
  - "What's due for Maya?" and "What should Maya do next?" are available.
  - Any intent that returns grades uses `authenticationPolicy = .requiresAuthentication` (SEC-WP-11).

### 6.7 Threat-model additions (extends security §3.3)

| Threat | Control | WP |
|---|---|---|
| **Leaked pairing code.** Anyone who enters it first becomes an observer. | 7-day single use (Canvas); a warning in the invite sheet; the code is never put in a URL, notification or log; **new-observer alert**. | FAM-06, 07 |
| **Shared family iPad.** A child's Safari SSO session silently authorises the parent flow, or the reverse. | `force_login=1` plus `canvas_login=1` on the parent path; the post-sign-in role check; the non-ephemeral default is kept for students only. | FAM-06 |
| **Wrong child's data shown.** A parent confuses siblings. | Name plus initials avatar always visible in the header and hero; per-subject cache keys; notification taps switch subject with a banner. | FAM-09 |
| **Stale data after unlink.** | Purge after 2 consecutive refreshes confirm the link is gone (§6.4). | FAM-05 |
| **Coercive or abusive monitoring.** An 18+ student cannot remove an observer. | Transparent **Who can see my Canvas**, the new-observer alert, a clear "ask your school" path. **Escalated to the owner and counsel as an ethical consideration**: Tally can't fix this, but mustn't hide it. | FAM-07, FAM-15 |
| **Write amplification** (API Policy non-GET clause). | Client throttle: at most 5 invite codes per student per day; W2 and W3 run only on an explicit tap. | FAM-06 |

### 6.8 Registry, admin kit and partner request

- **Registry entry** gains `family: { observers: Bool, inviteWrites: Bool, respectParentAppBlock: Bool }`. The school admin sets it during Tally setup. It has the same Ed25519 signing as today (WP-SEC-12).
- **`docs/go-to-market/school-admin-setup-guide.md`** needs an optional **"Family access"** block covering:
  - scopes S1, W1, O1, O2, O6, W2, W3;
  - a plain statement of the three write actions (API Policy §2B registration duty);
  - "requires self-registration = Observer or All for student invites".
  - Asking now is cheap. Adding scopes later means every school re-approves.
- **`docs/go-to-market/instructure-partner-request.md`** needs a paragraph on the parent view. The GL-01 ask should cover observer use explicitly, given the Canvas Parent overlap.
- **Ownership:** both documents belong to the GTM owner. This review does not edit them.

### 6.9 Cross-lane notes

- **Architecture:**
  - `Subject` / `SubjectKey`, the per-subject snapshot, and `RefreshCoordinator` fan-out per subject.
  - O2's course-level links need de-duplication with O1 by observee ID.
- **Encryption:** keyring scope `(accountKey, subjectKey, audience)`, `purge(subject:)`, and the no-names schema test for `accounts.json`.
- **Security:**
  - WP-SEC-01's authorize-URL builder gains `canvas_login`.
  - The SEC-SPIKE (WP-SEC-17) and FAM-01 should share one hosted-Canvas session.
- **UX lead:** owns the prototype. §7 is a spec for them to render; this review did **not** edit `first-run-prototype.html`.
- **Compliance:**
  - The privacy policy gains a "Parents and observers" section.
  - The review notes gain the 5.1.1(viii) rationale.
  - Sample mode needs a synthetic observer (FAM-14).
  - The label stays "Data Not Collected" under the recommended design (no Tally server, no new SDK); §5.2 would reopen it.
- **Pricing:**
  - §8 findings: per-product Family Sharing; multiseat on by default for new subscriptions; **Apple School Manager Volume Purchasing launches 2026-10-22**.
  - That last finding contradicts `pricing-licensing.md` §11.8's statement that Apple subscriptions "cannot be bought in volume". The pricing lane should re-check it. This review does not edit that file.

## 7. UX spec

It follows `ux-ui.md` §3.4:
- five tabs, each with its own `NavigationStack`;
- Settings as one sheet;
- a trailing toolbar holding `bell` and `person.crop.circle`;
- `Form`-based Settings.

### 7.1 Header student-switcher (parent mode)

- **Placement and control:**
  - `ToolbarItem(placement: .principal)` holding a `Menu`. Apple: in iOS the principal item sits in the centre of the navigation bar and "takes precedent over a title specified through `navigationTitle`". VERIFIED (docs).
  - **Why not `toolbarTitleMenu`:** Apple describes the title menu as actions on the content shown. Switching *whose* content is shown is a context change, so it belongs in an explicit control. VERIFIED (docs), design judgement.
  - **Where it appears:** on every tab root, so the context is global.
- **Label:**
  - A 28-pt circle with the student's initials, then the first name, then `chevron.down` (SF Symbol, `.caption2`).
  - Each student gets an avatar colour from a fixed 6-colour token palette where every pair passes ≥4.5:1 for the initials. Colour is never the only cue: the name is always shown.
  - Names truncate at 15 characters with a tail ellipsis. The HIG asks for titles "under 15 characters". VERIFIED (docs).
- **Menu content:**
  - a `Picker` with `.inline` style, so the current student gets a native checkmark, listing each student plus **Me** first when the account has its own coursework;
  - a `Divider`;
  - **Manage linked students…**, which opens Settings → Linked students;
  - **Add a student…**.
- **One student:** the label shows with no chevron and is **not** a menu. No dead controls (UX-12).
- **Zero students:** the switcher is replaced by the parent empty state (§7.6).
- **On switch:**
  - the content cross-fades, or uses an opacity-only transition under Reduce Motion;
  - `.sensoryFeedback(.selection)`;
  - VoiceOver hears the announcement "Now viewing Maya";
  - each student renders from their glance in under 300 ms, then refreshes if stale.
- **Hero:** reads "Maya's overall standing · Average of 5 courses" (owner O9 wording), so the student is named in content as well as in the bar.
- **Accessibility:**
  - label "Viewing Maya"; hint "Double-tap to switch student";
  - from AX1 upward, the label shows initials only, and the full names appear in the menu.
- **Deep links and notifications** for another student switch the subject and show a transient banner, "Switched to Leo".
- **Large titles:** how a principal item renders alongside a large navigation title on iOS 26/27 is UNVERIFIED. FAM-09 includes a snapshot test. Fallback: inline titles on tab roots in parent mode.

### 7.2 Student: Settings → "Family & Sharing"

| Row / element | Behaviour |
|---|---|
| Header text | "People linked to your Canvas account as observers (such as parents) can see your courses, assignments and grades in Canvas and in apps like Tally. They can't submit work or act as you." |
| **Invite a parent** (prominent) | §7.4. Hidden when `family.observers == false`; replaced by the school message and **Send an update…** |
| **Linked in Canvas** section | One row per observer from S1: initials avatar, name. Row → detail: "Linked to your Canvas account" + **How to remove** (§7.7). Footer: "Only account-wide links are shown. Links your school made for a single course may not appear." |
| **Invites from this iPhone** section | Label (e.g. "Mom") · "Expires Fri, Oct 2" · **Share again**. Footer: "Codes can't be cancelled. They stop working after 7 days or once used." |
| Toggle **Tell me when a new observer is linked** | Default on. |
| **Send an update…** | §5.1. Always available. |

### 7.3 Parent: Settings → "Linked students"

| Row / element | Behaviour |
|---|---|
| One row per student | Initials, name, school; a checkmark on the one being viewed. Row → detail. |
| Student detail | **Notifications for Maya** (the §6.5 kinds as toggles) · **Remove from Tally** · **Unlink in Canvas** (destructive, bottom). |
| **Add a student** | Code entry (§7.5 step 4) or **Scan code**. |
| Account section | School, "Signed in as <parent>" (a parent account), **Sign Out & Erase** (removes every student's data from this iPhone). |

### 7.4 Invite flow (student)

1. **Invite a parent** opens a sheet (`.medium` detent), "Let a parent see your Canvas".
   - It lists what the observer will see: courses, assignments and due dates, grades and comments, announcements, calendar.
   - It lists what they can't do: submit work, message as you, change anything.
   - Then: "Your parent signs in with **their own** account. You never share your password."
2. An optional field, "Who's this for? (only on this iPhone)", holds the local label.
3. **Create code** calls W1. On success:
   - a large monospaced code, letter-spaced, with an accessibility label spelling each character ("X, 7, Q…");
   - "Works once · expires Fri, Oct 2";
   - a QR code for scanning in person;
   - **Share…** and **Copy**.
4. A warning line under the code: "Anyone who enters this code first will be linked to you. Share it only with your parent."
5. The share-sheet text (no grades, and the code is never inside a URL):
   > I'd like you to see my <School> Canvas in Tally.
   > 1. Get Tally: <App Store link>
   > 2. Choose <School>, then "I'm a parent".
   > 3. Sign in or create your parent account.
   > 4. Enter code **X7Q2KP** (case-sensitive, expires Fri, Oct 2).
6. After 5 codes created on this iPhone are still pending, **Create code** warns: "Creating another code turns off your oldest unused one."

### 7.5 Parent onboarding and accept flow

1. **Welcome:** "I'm a student" / "I'm a parent or guardian".
2. **Find school** (registry). If `family.observers == false`: "Parent accounts aren't available at <School>'s Canvas." Offer **Done**. No dead end without an explanation.
3. **"Do you have a parent account at <School>?"**
   - **Sign in** runs the ADR 0001 handshake with `canvas_login=1&force_login=1`.
   - **Create one** opens Canvas's parent sign-up inside the same auth session. The parent enters the student's code there.
4. **Add your student**, if no observee is linked yet: a 6-character field (auto-caps off, because codes are case-sensitive), a `PasteButton` and **Scan code**. W2 runs on **Add**.
5. **First sync** uses the skeleton pattern from `ux-ui.md` §3.2 stage 5, labelled "Loading Maya's courses".
6. **Paywall** appears after the first successful sync, not before (§8; pricing §5.3 rules).

### 7.6 Empty and error states

| State | Copy | Action |
|---|---|---|
| Parent, no students | "No students linked yet. Ask your student for a code from Tally (Settings → Family & Sharing) or from Canvas (Account → Settings → Pair with Observer)." | **Add a student** |
| Student, no observers | "No one is linked to your Canvas account." | **Invite a parent** |
| Code rejected (`422` "Invalid pairing code.") | "That code didn't work. Codes are case-sensitive, work once, and expire after 7 days. Ask Maya for a new one." | **Try again** |
| Invite refused (`401`, school has no self-registration) | "<School> hasn't turned on parent accounts in Canvas, so Tally can't create an invite." | **Send an update…** |
| Scope missing on Tally's key | "Your school's Tally setup doesn't include parent invites yet." | **Get a code in Canvas** (Safari) · **Ask my school** |
| Student account used in parent mode | "This is a student account. Parents need their own Canvas parent account." | **Switch to student mode** · **Sign in as parent** |
| Link removed (by the school or by the student via the school) | "You're no longer linked to Maya in Canvas. Tally removed Maya's saved data from this iPhone." | **OK** |
| Offline / 2-h token expiry | Existing breadcrumb, per student: "Showing Maya's saved data from 2:14 PM" | ADR 0001 reconnect |

### 7.7 Unlink and removal confirmation copy (`.confirmationDialog`)

**Parent → "Unlink in Canvas"**
- **Title:** "Unlink Maya?"
- **Message:** "You'll stop seeing Maya's courses and grades in Tally, the Canvas Parent app and Canvas on the web. To link again, Maya will need to send you a new code. Tally will delete Maya's saved data from this iPhone."
- **Buttons:** **Unlink** (destructive) · Cancel.

**Parent → "Remove from Tally"**
- **Title:** "Remove Maya from Tally?"
- **Message:** "Maya stays linked to your Canvas account. Tally will delete Maya's saved data from this iPhone. You can add her back from Linked students."
- **Buttons:** **Remove from Tally** · Cancel.

**Student → observer row → "How to remove"** (a sheet, not destructive):
- **Heading:** "Only your school can remove an observer."
- **Body:** "Canvas doesn't let students unlink observers. Contact your school's Canvas support and ask them to remove <Name> as an observer on your account."
- **Buttons:** **Copy request** · Done.
- The copied text: "Please remove <Name> as an observer on my Canvas account (<login id>)."

**Student → Sign Out & Erase** gains one line: "Parents linked in Canvas can still see your courses and grades."

### 7.8 Accessibility acceptance (added to `ux-ui.md` §3.9)

- The switcher, the code field and the QR screen pass `performAccessibilityAudit()` at default and AX5 sizes.
- The code is read character by character.
- Every student-specific screen names the student in text.
- There are no colour-only cues.

## 8. Monetisation interplay

**Constraint:** the parent's app fetches from Canvas with the **parent's** token. The student's App Store subscription is tied to the **student's** Apple Account, and without a server Tally can't verify a different person's purchase. So "the student pays, and that covers the parent" is not implementable. The one exception is Apple's own mechanisms: Family Sharing, and later multiseat.

| Option | Who pays | How it works | Pros | Cons |
|---|---|---|---|---|
| A. Parent mode free | Nobody, for parents | No paywall in the observer role | Simplest; nothing irreversible | Zero revenue from parents. Tally becomes a free Canvas Parent alternative, which **raises** the "competitive" policy risk. Any observer anywhere gets it free. |
| **B. "Tally Family" subscription (recommended)** | Parent | A **new product** in the same subscription group, with Family Sharing **on for this product only**. The `.familyShared` ownership type grants children in the same Apple family group their student Tally. | Parent pays for parent value; children in the family are covered; "Tally Annual" ($9.99, sharing **off**) is untouched, so **P3 stands**. Family Sharing is per product ("configure which of your In-App Purchases are eligible", VERIFIED). | Irreversible **for Tally Family** (VERIFIED). Needs one Apple family group, which is common for K-12 Child Accounts and less so for college students (UNVERIFIED). Overlap if a child already pays: whether Apple prorates or refunds is UNVERIFIED (pricing lane). |
| C. Flip Family Sharing on for Tally Annual | Whoever buys | One $9.99 purchase covers up to 6 family members | No new product | Irreversible; breaks "per student" (up to 6 students for $9.99, pricing R8). **Not recommended.** |
| D. Group Purchases (multiseat) | Parent buys N seats of Tally Annual | Apple handles seat invitations. "Group Purchases will launch this winter"; multiseat is **on by default** for new subscriptions. | Keeps literal per-student pricing, parent-paid. | Not launched. StoreKit's representation of a seat holder is UNVERIFIED. If multiseat is on, "only the group purchaser is eligible for Family Sharing". Revisit (BL-F3). |

**Recommendation (owner decision F5):**
- Keep **P3** (Family Sharing off on Tally Annual) for v1.
- When family linking ships, add **Tally Family**, bought by the parent, with Family Sharing on for that product only. The pricing lane sets the price. Comparables in `pricing-licensing.md` §2.1: Grade Corner family $29.99, MyStudyLife family $59.99–$119.99. A $19.99–$29.99 test range is analysis, UNVERIFIED.
- Parent mode requires Tally Family, with the same 1-month free trial.
- The paywall follows the GL-01 gate: shown only after a successful observer sync.
- Re-evaluate Group Purchases when Apple ships it.
- **Pricing lane action:** new subscriptions default to multiseat **on**. Decide deliberately before creating Tally Annual, because multiseat and Family Sharing interact.

## 9. Owner decisions

| # | Decision | Options | Recommendation | Consequence |
|---|---|---|---|---|
| **F1** | How the parent gets access | (a) Parent's own Canvas observer account + student's pairing code; (b) parent uses the student's credential | **(a)** | (a) is native, compliant, read-only by construction, and no credential leaves a device. (b) lets the parent act as the student, breaks R3/ADR 0001 and the API Policy, and fails under refresh-token rotation (§3). |
| **F2** | R16 (read-only) | (a) **R16a**: allow three tap-initiated link writes (create code, add by code, unlink); (b) strict R16: Tally deep-links to Canvas web for every link action | **(a)**, with (b) as the automatic fallback when the scope is missing | (a) gives the in-app invite the owner asked for; schools must grant 3 write scopes, and the writes must be disclosed. (b) needs no new write scopes, but the invite leaves Tally for Safari. |
| **F3** | R8 (single account) | (a) **R8a**: one account, many subjects; (b) keep R8, one student per parent install | **(a)** | (a) delivers the header switcher. Cross-school families still need BL-05. |
| **F4** | Schools without observers | (a) "Send an update…" share sheet only; (b) also a CloudKit live share | **(a)**; (b) to backlog BL-F1 | (a) has no policy exposure and tiny cost. (b) is fresh-as-student, needs ADP for true E2E, and risks the school's key. |
| **F5** | Who pays | A free parent mode · **B Tally Family (parent pays, sharing on for that product only)** · C sharing on for Tally Annual · D wait for Group Purchases | **B** | See §8. Irreversible for the new product only. |
| **F6** | Sequencing and Instructure | (a) Add family use to the GL-01/GTM-02 request **now**; add optional family scopes to the school-admin guide now; **build in v1.1 after FAM-01**; (b) build in v1 | **(a)** | (a) keeps v1 scope intact and surfaces the Canvas Parent overlap to Instructure before we invest. (b) adds ~15 WPs to v1 and more policy risk at launch. |
| **F7** | Parent notification defaults | (a) Week-ahead + missing-still-open on, others off, names shown with a "Hide student names" toggle; (b) everything off | **(a)** | (a) is useful without nagging a child through a parent's phone. |
| **F8** | Coercive-monitoring stance (ethical) | (a) Transparency: "Who can see my Canvas" + new-observer alert + school path; (b) also ask Instructure for a student-side unlink (BL-F4) | **(a) + (b)** | Tally can't remove observers, but it mustn't hide them. Counsel to review the copy (GL-03). |

## 10. Work packages

Verification legend (as in security §5):
- **Linux**: Swift 6.4 container.
- **macOS CI**: simulator.
- **device / real Canvas**: physical iPhone or hosted Canvas.

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| **FAM-01** | **Real-Canvas observer spike (gates the build)**; writes ADR 0002 | GL-01 key at a pilot school or Instructure sandbox; WP-SEC-17 session | ADR records evidence for each question, answered with a real response: (1) W1 with Tally's scoped public key succeeds, and returns 401 when self-registration is None; (2) code length, 7-day `expires_at`, single use; (3) parent OAuth with `canvas_login=1&force_login=1` reaches Canvas login; whether sign-up inside `ASWebAuthenticationSession` continues OAuth; (4) O3 returns observee scores; `hide_final_grades` behaviour; (5) O5 returns per-student overridden due dates; (6) a student calling `DELETE /users/:observer/observees/:self` gets 401; (7) W3 works for the observer; (8) whether Canvas notifies the student of a new link | curl on the Linux host + device, against hosted Canvas; pre-run on local OSS Canvas |
| FAM-02 | Role and subject domain (`Capability`, `Subject`, `SubjectKey`, `activeSubject`) | ARC A-series | Fixtures: student-only / parent-only / both / parent with 0 observees → correct capabilities and subject list. `SubjectKey` is stable and contains no names (test). `activeSubject` persists as an opaque key in `user-state`. | Linux |
| FAM-03 | Endpoint catalog S1, W1–W3, O1–O7 + scope list + observer fixtures in `fixtures/canvas/observer/` | FAM-02, ARC B-series | Every endpoint decodes its fixtures (success, 401 with and without `WWW-Authenticate`, 422 invalid code). W2 sends `pairing_code` in the form body, never in the query (test on the built `URLRequest`). A scope-list test equals the admin-guide table. | Linux (URLProtocol stubs) |
| FAM-04 | Observer snapshot composition + per-subject partial failure | FAM-03, ARC WP-B06 | The 2-observee/6-course fixture yields 2 subject snapshots. O4 is called once per course, not per observee. A failing subject doesn't fail the others. Request count is logged and ≤ 26 on the fixture. The parity rule hides totals when `hide_final_grades` (test). | Linux |
| FAM-05 | Per-subject sealed storage + `purge(subject:)` + link-disappearance purge | ENC TallyVault, ARC WP-C02 | `.me` uses existing paths (no-migration test). Keyring scope includes `subjectKey`. A blob resurrected after purge gives `keyMissing`. A schema test proves `accounts.json` has no names. The purge fires only after 2 consecutive refreshes confirm the link is gone. | Linux |
| FAM-06 | Link-management use cases: CreateInvite, ListObservers, AddStudentByCode, UnlinkStudent, RemoveFromTally; error mapping; throttle; registry `family` gating; `canvas_login`/`force_login` on the parent path | FAM-03, WP-SEC-01/03/12 | Each error row in §7.6 maps from its stub. Throttle: the 6th invite in 24 h is refused locally (config value, clock-injected test). The code never appears in log output (logging-facade test). A parent authorize URL always carries both flags. | Linux |
| FAM-07 | New-observer detection alert | FAM-06, insights R13 pipeline | The first refresh seeds silently. A new observer ID yields exactly one alert plus an optional notification with no names. A removed observer yields no alert. | Linux |
| FAM-08 | Parent notification planner + content builder (R10a) | WP-SEC-10, insights §3.8 | Property test: over all fixtures, parent notification text never contains a score, percentage or letter grade taken from the snapshot. "Hide student names" replaces every name. Per-subject thread IDs. The 64-cap split keeps a floor of 4 per subject. | Linux |
| FAM-09 | Header student-switcher (§7.1) | FAM-02, UX-WP-05 | XCUITest: switching on Dashboard persists across all 5 tabs. One student shows no menu. Accessibility audit: 0 unwaived issues at default and AX5. VoiceOver announcement fires. The large-title rendering snapshot is recorded. | macOS CI |
| FAM-10 | Settings: Family & Sharing (student) + Linked students (parent); invite, accept, unlink flows; §7.6 states; §7.7 copy | FAM-06, UX-WP-20 | One UI test per state against a stubbed Canvas in sample mode. Confirmation copy matches §7.7 verbatim (string-table test). No dead rows. | macOS CI |
| FAM-11 | Widgets + App Intents with a `StudentEntity` | FAM-05, UX widget WPs | Widget snapshot tests per student. Locked redaction of opt-in grades. Grade-returning intents require authentication. | macOS CI + device |
| FAM-12 | Registry `family` block; school-admin guide "Family access" block; partner-request paragraph (drafts for the GTM owner) | WP-SEC-12, F2, F6 | Registry decode and signature tests with the new fields. Drafts reviewed by the PMO. Guide lists S1, W1–W3, O1, O2, O6 and the three write actions. | Linux + doc review |
| FAM-13 | StoreKit "Tally Family": entitlement for observer role, `.familyShared` handling, paywall after first observer sync | pricing PAY-WPs, F5 | StoreKit Test config covers purchased / familyShared / expired / revoked. No paywall before a successful observer sync (UI test). | macOS CI + sandbox device |
| FAM-14 | Sample-data family mode: a synthetic observer with 2 students | ASC-14, `fixtures/canvas/` | Fixtures decode with the production decoders. App Review can reach the parent mode, switcher and Linked students from "Explore with Sample Data" (UI test). | Linux + macOS CI |
| FAM-15 | Privacy policy "Parents and observers" section; App Review notes (5.1.1(viii) rationale); counsel items added to GL-03 (FERPA reading, coercive-monitoring copy) | ASC R4, GL-03 | The compliance script still passes `NSPrivacyCollectedDataTypes == []`. The policy text covers who sees what, how to unlink, and what Tally stores. GL-03 lists the two new items. | Compliance script + doc review |

## 11. Backlog items

Proposed IDs; the PMO assigns final `BL-` numbers when the owner accepts an item into `docs/BACKLOG.md`.

| ID | Enhancement | Why deferred | Revisit when | Notes |
|---|---|---|---|---|
| BL-F1 | Student-controlled live share via CloudKit (`CKShare` + `encryptedValues`) for schools without observers | API Policy "third-party" exposure; true E2E only with ADP; only as fresh as the student's last refresh (§5.2) | Instructure's written OK **and** pilot demand evidence | Would need Tally's own HPKE layer for unconditional E2E, plus a privacy-label re-analysis. |
| BL-F2 | Cross-institution families (children at two schools) | Needs two observer credentials = BL-05 | BL-05 is scheduled | Switcher groups students by school. |
| BL-F3 | Group Purchases (multiseat) as parent-paid, per-student seats | Apple launches "this winter"; StoreKit seat representation UNVERIFIED | Apple GA + StoreKit docs | Interacts with Family Sharing (only the group purchaser shares). |
| BL-F4 | Ask Instructure for a student-side observer-removal API | Canvas lacks it (§2.4) | GL-01 / GTM-02 conversation | A GTM ask, not engineering. |
| BL-F5 | Canvas `observer_alerts` / thresholds integration | Writes, and it replicates Canvas Parent | Not planned | Listed so nobody builds it by accident. |

## 12. Sources

Accessed 2026-09-26 unless stated.

| URL / location | What it established | Status |
|---|---|---|
| https://canvas.instructure.com/doc/api/user_observees.html | Endpoint list (list observees and observers, add with credentials or code, show, PUT, DELETE, create pairing code); scope strings; "all users are allowed to list their own observers" | VERIFIED (docs) |
| https://developerdocs.instructure.com/services/canvas/resources/user_observees | PairingCode object: `user_id`, `code`, `expires_at`, `workflow_state`; lifetime not stated there | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/388738-pairing-codes-faq (updated 2026-02-12) | 6-char, case-sensitive; 7 days or first use; five active; needs self-registration; one code per observer; Parent app can't generate; student web + Student iOS app can | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/661195-how-do-i-generate-a-pairing-code-for-an-observer-as-a-student (2026-09-14) | Account → Settings → Pair with Observer; missing button → contact institution | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/661631-how-do-i-send-a-pairing-code-to-an-observer-in-the-canvas-app-on-my-ios-device (2026-03-25) | Student iOS app shows code + QR + Share; requires self-registration | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/662734-what-is-the-observer-role (2026-05-19) | Account- vs course-level links; what observers can and can't do; access varies by institution | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/661365-how-do-i-sign-up-for-a-canvas-account-as-a-parent (2026-06-29) | Parent sign-up with one pairing code; registration banner only if enabled; Parent app access controlled by the institution | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/661368-how-do-i-link-a-student-to-my-user-account-as-an-observer (2026-06-29) | Observing page add/remove; same-institution limit | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/661760-… , …/661768-… , …/661772-… (Parent iOS guides, 2026-02 to 2026-05) | Parent app account creation, Student Selector / Manage Students, QR pairing, alerts | VERIFIED (docs) |
| https://community.instructure.com/en/kb/articles/661429-how-do-i-configure-canvas-authentication-details-for-an-account (2026-09-11) | Self-registration off by default; "Observer Accounts Only" / "All Account Types" | VERIFIED (docs) |
| `canvas-lms` master `1c9f0bb801`: `observer_pairing_codes_api_controller.rb:59-66`; `models/user.rb:1470-1494, 1519-1520, 1573-1574, 3986-3993`; `models/observer_pairing_code.rb`; `models/account.rb:655-677`; `models/authentication_provider/canvas.rb:43-61`; `user_observees_controller.rb:50-88, 125-182, 264-275, 313-317`; `courses_controller.rb:507-509, 669-670`; `assignment_groups_controller.rb:107-112`; `assignments_api_controller.rb:789-795, 822-825, 1825-1834`; `planner_controller.rb:64-67, 182-199`; `calendar_events_api_controller.rb:376-380, 2089-2101`; `lib/api/v1/user.rb:345-346, 413-420`; `models/enrollment.rb:1405-1406`; `oauth2_provider_controller.rb:108-117`; `login_controller.rb:55`; `config/routes.rb:1045-1059, 1847-1854, 1886-1901` | Pairing rules, self-registration gate, 7-day 6-char code, single use, student can't DELETE observer links, observer read rights, `observed_users` includes, planner and calendar observer access, `canvas_login` pass-through | VERIFIED (OSS); hosted UNVERIFIED |
| `canvas-ios` `195fb97b21`: `Core/Core/Features/Profile/Settings/APIPairingCode.swift:49, 81-84`; `Core/Core/Features/Users/User/API/PostObserveesRequest.swift`; `Core/Core/Features/ObservedStudents/GetObservedStudents.swift` | Instructure's apps: student POST pairing code; parent POST observees (code in query); parent sign-up via `POST /accounts/:id/users`; observees discovered via enrollments + `observed_users` | VERIFIED (OSS) |
| https://www.instructure.com/policies/canvas-api-policy (effective 2025-08-12) | §2A mirror/replicate; §2B "on behalf of any third-party", registration must outline actions; §2C disclosure; §2D notice before more permissive practices; §3 competitive purposes; non-GET revocation | VERIFIED (docs) |
| `docs/pmo/reviews/security.md` §2 SEC-02, §3.2, §7 | Refresh-token rotation for public clients; "Access tokens are password equivalent"; 401 scope vs token handling | VERIFIED (per that review) |
| https://studentprivacy.ed.gov/faq/what-ferpa | Rights transfer at 18 or postsecondary ("eligible student") | VERIFIED (docs) |
| https://www.ecfr.gov (title 34 part 99, current to 2026-09-09): §§99.3, 99.5, 99.30, 99.31(a)(8), (a)(15), (d) | Eligible-student definition; transfer of rights; written-consent elements; dependent-student and under-21 exceptions; exceptions permissive | VERIFIED (docs); application to Tally UNVERIFIED (counsel) |
| https://developer.apple.com/app-store/review/guidelines/ (last updated 2026-06-08) | 5.1.1(i), (ii), (viii); 5.1.2(i), (ii) | VERIFIED (docs) |
| https://developer.apple.com/documentation/cloudkit/ckshare ; …/ckrecord/encryptedvalues | Zone and hierarchy sharing, `UICloudSharingController`, `CKSharingSupported`; on-device encryption; keys exclusive to owner and participants **with ADP** | VERIFIED (docs) |
| https://support.apple.com/en-us/102651 (published 2026-01-05) | Standard protection: keys in Apple data centres; CloudKit encrypted fields E2E only with ADP | VERIFIED (docs) |
| https://developer.apple.com/app-store/app-privacy-details/ | "Collect" definition; not responsible for data Apple collects via CloudKit | VERIFIED (docs) |
| https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases | Per-product configuration; up to five additional members; can't turn off; multiseat interaction | VERIFIED (docs) |
| https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-purchase-options-for-auto-renewable-subscriptions | Multiseat on by default; group purchaser controls access; Apple School Manager volume purchase | VERIFIED (docs) |
| https://developer.apple.com/news/?id=likeohx4 (2026-09-16) | Volume Purchasing launches 2026-10-22; Group Purchases "this winter" | VERIFIED (docs) |
| Apple docs: `Transaction.OwnershipType.familyShared`; `Product.isFamilyShareable` | On-device family-shared entitlement | VERIFIED (docs) |
| Apple docs: `ToolbarItemPlacement.principal` (iOS 14); `View.toolbarTitleMenu(content:)` (iOS 16); HIG *Toolbars* | Principal item centred and overrides the title; title menu is for content actions; titles under 15 characters | VERIFIED (docs) |
| Prevalence of self-registration or observers in higher education | No data found | UNVERIFIED |
