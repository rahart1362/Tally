# STORE-COPY-1 report: App Store listing draft (owner approval: 2026-10-21)

**Status: DRAFT. Every line needs the owner's line-by-line approval before this PR merges** (brief, "Owner approval: 2026-10-21"). Nothing here has been submitted anywhere; it only exists in this branch's files.

Locales: `en-US` (primary, hand-written) and `es-MX` (**machine pass** — see §3). Deliverables: `docs/release/app-store/<locale>/{name,subtitle,keywords,promotional_text,description,review_notes}.txt`, the per-locale `check_release.py` metadata check, and `site/admin/index.html` (EB-23).

## 1. Metadata files: length and guardrails

All lengths below are the actual bytes/characters `check_release.py`'s new `metadata_checks()` measures (keywords in UTF-8 bytes; everything else in characters, per App Store Connect and `app-store-compliance.md` §3.5). Full text lives in the files themselves; short fields are reproduced here, the two long fields (`description.txt`, `review_notes.txt`) are only summarized to keep this table readable.

| File | Locale | Length / limit | Text (short fields) or summary (long fields) | Guardrail checks |
|---|---|---|---|---|
| `name.txt` | en-US | 25 / 30 | "Tally: Grades & Due Dates" | EB-14 (no "Canvas"); EB-15 (no age/kids wording) |
| `name.txt` | es-MX | 23 / 30 | "Tally: Notas y Entregas" | same, Spanish; "Notas" = grades (common MX usage) |
| `subtitle.txt` | en-US | 29 / 30 | "Grades, deadlines & reminders" | EB-14; EB-15 |
| `subtitle.txt` | es-MX | 24 / 30 | "Notas, entregas y avisos" | same |
| `keywords.txt` | en-US | 98 / 100 (bytes) | `grades,gpa,assignment,due date,student,planner,homework,school,what-if,deadline,exam,course,widget` | EB-14 (no "canvas"); no app-name repeat; no "kids"/"children" (EB-15) |
| `keywords.txt` | es-MX | 95 / 100 (bytes) | `calificaciones,promedio,tarea,fecha límite,planificador,escuela,curso,examen,pendientes,widget` | same; byte-counted because of accents (í) — this is exactly why the check counts bytes, not characters |
| `promotional_text.txt` | en-US | 144 / 170 | "Every grade, due date and reminder for your classes, in one fast, private app — with widgets, Shortcuts and a What-If grade calculator built in." | No "Canvas" (EB-14 restricts it to the description only); no pricing/"free" claim (avoids EB-24(b) entirely by not making one here) |
| `promotional_text.txt` | es-MX | 152 / 170 | Spanish translation of the above | same |
| `description.txt` | en-US | 2,473 / 4,000 | Value prop; a bullet per shipped feature (Dashboard, Courses, Course Detail + What-If, To-Do, Calendar, Insights, Reminders, widgets, Shortcuts/Siri, Family); a qualified privacy paragraph; a pricing/trial paragraph that states the renewal price and that it auto-renews; "Works with Canvas LMS…" nominative line; the verbatim disclaimer | EB-14 ("Works with Canvas" confined to this field only); EB-15 (no age/minors wording anywhere); EB-16 (verbatim disclaimer, last line); EB-24(a) (qualified "no server" claim, not an absolute "nothing leaves this device"); EB-24(b) (states the post-trial price and that it renews); EB-24(c) (no school-search / discoverability claim); EB-24(d) (no purchase urgency) |
| `description.txt` | es-MX | 2,850 / 4,000 | Spanish translation of the above, including the app's own shipped Spanish disclaimer string (not re-translated by me — see §3) | same |
| `review_notes.txt` | en-US | 3,204 / 4,000 | **Unchanged** — the brief said "already written; keep it" | n/a (not my text) |
| `review_notes.txt` | es-MX | 3,680 / 4,000 | Spanish translation of the kept en-US file | machine pass, see §3 |

Verified by re-running `metadata_checks()` against the real files after writing them (not just the drafts): `RELEASE | PASS | M5 | REL.metadata.store-listing.en-US | … | all within limits` and the same for `es-MX` (`python3 scripts/ci/check_release.py --source . --json /tmp/…/source.json`). `python3 scripts/ci/check_release.py --self-test` passes (33 checks).

## 2. Sources for each claim in the description

| Claim | Source |
|---|---|
| Dashboard: overall standing, trend, momentum streak | `packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardView.swift:65-68,338-362` (just-merged FEAT-1, PR #62) |
| Courses: current grade + trend sparkline | `apps/TallyiOS/TallyUITests/StoreScreenshotUITests.swift:10-13` (scene inventory, "Courses with the sparklines") |
| Course Detail + What-If, local-only, never writes to Canvas | `packages/TallyAppleKit/Sources/TallyStrings/L10n.swift:236` (`courseDetail.whatIf.button`); `docs/pmo/reviews/xg04-06-report.md:3` ("nothing is saved"); `docs/pmo/02-program-plan.md` R16 ("Tally never writes to Canvas") |
| To-Do: everything due, across courses | `apps/TallyiOS/TallyUITests/StoreScreenshotUITests.swift:12` |
| Calendar: per-item Add to Calendar + Canvas calendar subscription | `packages/TallyAppleKit/Sources/TallyStrings/L10n.swift` `calendar.optionsMenu.subscribe`; `docs/pmo/02-program-plan.md` R6 (no EventKit permission prompt) |
| Insights: next up, week-ahead, trends | `packages/TallyAppleKit/Sources/TallyStrings/L10n.swift` `widget.header.nextUp`/`weekAhead`; `docs/pmo/02-program-plan.md` R13 |
| Reminders: day-before + hour-before default, hide course names | `packages/TallyAppleKit/Sources/TallyStrings/L10n.swift:500-544` (`reminders.tip.body`, `reminders.hideCourseNames`); R14 |
| Home/Lock Screen widgets, mark done | `packages/TallyAppleKit/Sources/TallyStrings/L10n+Widgets.swift:19-97`; `apps/TallyiOS/TallyWidgets/MarkDoneIntent+Widget.swift` |
| Shortcuts/Siri | `apps/TallyiOS/Tally/Intents/DueIntents.swift`, `apps/TallyiOS/Tally/Intents/TallyFocusFilter.swift` |
| Family: parent/guardian via Canvas's own observer account + pairing code | `packages/TallyAppleKit/Sources/TallyFeatures/Family/FamilyModel.swift:137-138` (`addStudent(pairingCode:)`), `FamilySettingsViews.swift:280-585` (real pairing-code flow — **not just sample mode**; see open item below) |
| No Tally account/server; Sign Out & Erase | `site/privacy/index.html` ("There is no Tally account…"); `docs/pmo/02-program-plan.md` R2/R3 |
| Qualified "data stays on device" claim (calendar subscription + school-list static-host exception) | `site/privacy/index.html` ("Finding your school…", "Calendar…" paragraphs); `/home/rahart1362/Documents/Tally-compliance/us-wide/engineering-backlog-us.md` EB-24(a) (LOCAL, cited not copied) |
| $9.99/year price | `docs/pmo/02-program-plan.md` §2b P1 |
| 2-week free trial, renews automatically, disclosed | Brief, "Added 2026-10-21" (owner decision, 2026-10-21) — **see open item: not yet reflected in `Products.storekit` or `02-program-plan.md` P1, both of which still say "1-month"** |
| "Works with Canvas LMS…" nominative phrase confined to the description | `/home/rahart1362/Documents/Tally-compliance/engineering-backlog.md` EB-14 (LOCAL, cited not copied) |
| Verbatim disclaimer | `packages/TallyAppleKit/Sources/TallyStrings/L10n.swift:355` (English); `apps/TallyiOS/TallyAppTests/Fixtures/L10N04SpanishFixture.swift:9` (the app's own shipped Spanish translation, reused verbatim rather than re-translated) |
| Admin guide content (site/admin/index.html) | `docs/go-to-market/school-admin-setup-guide.md` (steps, scopes, the GL-05 "being verified" flag, the "as read on 2026-09-26" flag — both kept, not resolved); `packages/TallyAppleKit/Sources/TallyStrings/L10n.swift` `adminRequestText`/`askMySchool` (confirms this is the page the share-sheet message links to, via `TallyOrgDomainInfo.current` + `/admin`) |

## 3. Spanish (es-MX): machine pass

Per the owner's L10N rule, **every es-MX file in this PR is a machine translation pass, not reviewed by a native speaker.** I built it with the app's own already-shipped Spanish vocabulary where one exists (`L10N04SpanishFixture.swift`: "Tablero", "Calificaciones", "Por hacer", "Recordatorios", "Atajos", "Fechas de entrega", "Cerrar sesión y borrar", etc.) so the store listing doesn't introduce new terms that disagree with the app's UI. The one deliberate exception is `name.txt`/`subtitle.txt`, which use "Notas" instead of the UI's "Calificaciones" for brevity under the 30-character limit — flagging this specifically for the native-speaker review `08-localization-and-external-grades.md` L-1 calls for, since "Notas" can also read as "notes."

The es-MX disclaimer line in `description.txt` is **not** my own translation — it's the exact string the app already ships in `L10N04SpanishFixture.swift:9`, reused verbatim for EB-16 harmonization.

## 4. Alternatives for the owner to choose from

**Two alternative subtitles** (en-US; both ≤30 characters, no "Canvas", no age/kids wording):
1. "Due dates, grades & widgets" (27)
2. "Reminders, widgets, insights" (28)

**Two alternative keyword sets** (en-US; both ≤100 bytes, no "canvas", no app-name repeat):
- Set B: `assignments,gpa calculator,due dates,homework planner,grade tracker,college,reminders,widget,agenda` (99 bytes)
- Set C: `to do,deadlines,course grades,gpa tracker,homework,study planner,reminders,widget,siri,shortcuts` (96 bytes)

## 5. `check_release.py` change

`METADATA_DIR` ("docs/release/metadata", a flat folder) is replaced by `METADATA_ROOT` ("docs/release/app-store") + `METADATA_LOCALES = ("en-US", "es-MX")`. The inline check in `source_checks()` is extracted into a new standalone `metadata_checks(root, due="M5")`, matching the existing pattern for `a11y_audit_checks`/`screenshot_checks`: one `Check` per locale, `REL.metadata.store-listing.<locale>`, same "nothing passes by being missing" rule (an absent locale folder reports every file missing rather than being skipped). The check's due milestone is unchanged (`M5`).

`--self-test` gained a new block (using `tempfile.TemporaryDirectory()`, since this check is the only one in the file that reads real files from disk) covering: a complete locale passing, a wholly-missing locale reporting every file and settling PENDING (M5 is after the MVP `CURRENT_MILESTONE`), an over-limit file failing the check's own `ok` with the right message, the byte-vs-character distinction for `keywords.txt` specifically (a 60-character/120-byte string fails only the byte-counted file), and that an explicit `due` argument is honoured. `python3 scripts/ci/check_release.py --self-test` passes locally (33 checks, up from 29).

No other file references the old `METADATA_DIR`/`docs/release/metadata` path (checked with `grep -rl` across `*.py`/`*.yml`/`*.md`), except `docs/pmo/08-localization-and-external-grades.md` line 192, which already anticipated `docs/release/app-store/es-MX/` as the destination — this change matches that doc, not contradicts it.

## 6. `site/admin/index.html` (EB-23)

Drafted in the existing site style (`site/_style.css`, structured like `site/support/`), covering exactly the brief's four bullets: what Tally is / no server / no student accounts; what a Canvas admin does to enable it (condensed from `docs/go-to-market/school-admin-setup-guide.md`, keeping both of that doc's own "unverified"/"confirm" flags — the Public client-type UI option (GL-05) and the scope strings' currency — rather than resolving them myself); a Privacy section linking `/privacy/`; a Contact section linking `/support/`. It also carries the verbatim EB-16 disclaimer and an in-page "DRAFT-PENDING-OWNER-APPROVAL" banner, since pushing to `main` publishes the site (`site/CNAME`) and this PR is a draft.

**Observation, not fixed (out of my file ownership):** `site/index.html` and `site/privacy/index.html` each already carry a *shortened* disclaimer ("…is not affiliated with or endorsed by Instructure…", dropping "endorsed by, or sponsored by" and "Inc."), which differs from the verbatim L10n string EB-16 asks to harmonize on. My new page uses the verbatim string; the two existing pages don't. Flagging for whoever owns `site/index.html`/`site/privacy/index.html` to reconcile — I only touched `site/admin/`.

## 7. Open items (not resolved by this PR)

1. **Trial-length mismatch.** This copy says "2-week free trial" per the brief's 2026-10-21 owner decision. `apps/TallyiOS/Config/Products.storekit` and `docs/pmo/02-program-plan.md` §2b P1 still configure/record a **1-month** trial (confirmed by grep; `docs/pmo/reviews/m3b1-report.md:21` describes the shipped StoreKit config). Whoever owns the StoreKit configuration must update it to 2 weeks before submission, or this copy will overclaim against what the paywall actually offers (EB-24(b) risk). Not in my file ownership for this WP.
2. **`review_notes.txt` (en-US) looks stale on parent linking.** It says "[AT SUBMISSION] Real-account parent linking is not part of this build," but `FamilyModel.swift:137-138` and `FamilySettingsViews.swift` show a real (non-sample) pairing-code flow already implemented. Per rule 8 I'm trusting the code and citing it above, but I did not edit `review_notes.txt` — the brief said to keep it as already written, and it isn't on my ownership list.
3. **EB-24(c), school search.** I kept "Ask My School" / school search entirely out of the public-facing marketing copy (name/subtitle/keywords/promotional_text/description), per the owner's "no school-search claims until that ships" instruction. It only appears in `site/admin/index.html`, which is operational (addressed to admins, not marketing).
4. **EB-24(e).** Re-review the final store listing against FTC Act §5 before each actual submission — a process step for the owner/counsel at submission time, not something this draft resolves.
5. **es-MX needs the paid native-speaker review** `08-localization-and-external-grades.md` L-1 calls for before it's used for real; it's a machine pass today, per the owner's L10N rule.
6. Whether the US App Store storefront shows `es-MX` metadata to Spanish-language devices is itself unverified (the same open question `08-localization-and-external-grades.md:192` already flags) — confirm in App Store Connect at M5.


## 8. Owner approval (2026-10-21)
- **Approved:**
  - name "Tally: Grades & Due Dates";
  - subtitle "Grades, deadlines & reminders" (the draft);
  - keyword set A (the draft);
  - the promotional text;
  - the description, with two edits.
- **Edit 1 (applied):** the reminders line now says "Notifications never show grade values, and widgets show them only if you turn that on." Verified: grade values never appear in notifications (R10), and widgets show them only with Settings → "Show Grades in Widgets" (`SettingsModel.swift:11,29`; `GlanceTimeline.swift:139`). The default reminders are T-24h and T-1h (`ReminderPlanner.swift:106-116`).
- **Edit 2 (a submission step):** the Family bullet stays only if the real-account family flows (moved to M4; plan 02 §M3 exit) ship before submission; otherwise remove it at submission.
- **The `/admin` page:** approved as drafted, to be published on merge.
- **es-MX:** follows as a machine pass for the native reviewer.
