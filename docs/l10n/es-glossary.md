# Spanish (es) glossary — for the native-speaker reviewer to confirm

**Status: machine pass (2026-10-11), not reviewed.** Every Spanish value in the catalogs is
`needs_review` (plan 08 L10N-04; owner decision 2026-10-11, "machine pass now, review later").
This glossary records the term choices the machine pass made consistently, so the paid
native-speaker reviewer can confirm or correct them once, rather than per occurrence. A change here
should be applied with `scripts/l10n/es_review.py apply`, not by hand-editing the catalogs.

## Variant and voice

- **Variant: neutral Latin American / US Spanish (`es`), not `es-ES`.** The audience is US
  students and their parents (plan 08 §3, app-store-compliance R6). Regional formatting (percent
  sign placement, decimal comma vs. point) still follows the device's own region through
  `TallyLocale.effective`/`TallyFormat` — this glossary is about word choice, not number
  formatting.
- **Voice: informal "tú"**, for both the student-facing and the parent-facing (family feature)
  text. The English parent-facing copy is itself informal in tone (e.g. "Add a Student", "Who's
  this for?"), so tú carries over directly; nothing in the family screens reads as needing a formal
  "usted" register. **Reviewer: confirm this holds**, especially for the parent-onboarding sheets
  (`family.invite.*`) and the school-facing share text (`grades.info.shareText*`,
  `onboarding.schoolSearch.adminRequestText`), which address a third party (the school) rather than
  the student or parent directly and so are phrased as a request ("¿Podría la escuela
  considerar...?", "¿Considerarían habilitar Tally...?").
  **Correction (L10N-04 round 2, gate-2 verdict T30):** this note previously claimed school-facing
  text used "neither tú nor usted" — inaccurate. `onboarding.schoolSearch.adminRequestText` mixed
  ustedes ("¿Considerarían...?") with a stray tú ("con tu Canvas"), found by the gate-2 review
  (T11) and fixed in round 2 (now "con el Canvas de la escuela", no second-person pronoun).
  Reviewer: confirm no other school-facing string has the same slip.

## Canvas vocabulary (the PMO's seed; confirm against Canvas's own Spanish UI)

Matched so students recognise the words from Canvas itself:

| English | Spanish | Where it appears |
|---|---|---|
| Dashboard | Tablero | `dashboard.navigationTitle`, `home.tab.dashboard`, and throughout Dashboard copy |
| Courses | Cursos | `courses.navigationTitle`, `home.tab.courses`, `subscription.feature.*` |
| Grades | Calificaciones | `courseDetail.segment.grades`, `subscription.feature.grades`, throughout |
| Assignments | Tareas | `courseDetail.segment.assignments`, `widget.hiddenAssignment`, throughout |
| Announcements | Anuncios | not yet a standalone UI string in the current catalog (Canvas content is `Text(verbatim:)`); recorded for when one is added |
| Calendar | Calendario | `calendar.tabTitle`, `home.tab.calendar` |
| To-Do | Por hacer | `todo.navigationTitle`, `home.tab.toDo`, `subscription.feature.dueDates` |
| Missing | Faltante | `todo.status.missing`, `courseDetail.section.missing` |
| Late | Atrasado | `todo.status.late` |
| Submitted | Entregado | `todo.status.submitted`, `courseDetail.section.submitted` |
| Excused | Justificado | `todo.status.excused` |
| Due | Vence (verb form) / Fecha de entrega (noun form) | "Vence %@" (`courses.formatter.dueDay` and similar); "Fecha de entrega" (`todo.sort.dueDate`) |

**Reviewer: confirm every row** against Canvas's own Spanish localization, which this pass did not
have direct access to (no secondary source was consulted beyond the PMO's seed table in the brief).

## Terms this pass chose, not in the PMO's seed

These recur across catalogs; keep them consistent if correcting one occurrence.

| English | Spanish chosen | Why / alternatives considered |
|---|---|---|
| Overdue (`dashboard.reason.overdue`) | Vencido | Distinct from "Atrasado" (the glossary's own word for "Late"/`todo.status.late`), since English also uses two different words. Reviewer may prefer merging these to one word. |
| Past due (`notification.missing.noClosingDate`, `family.notification.missing.noClosingDate`) | Atrasado | Treated as the same concept as "Late", not "Overdue" |
| Next Up / Next up (widget header, Dashboard section header, the Next Up widget/control gallery name, the App Intents destination) | Lo próximo | Chosen over "Próximamente" or "A continuación" because the L10N-01 spike (`docs/pmo/reviews/l10n-infra-report.md` §2, Q3) already observed Xcode rendering the **widget gallery's** Spanish name as "Lo próximo" in a real simulator run (36775064980); this pass extended the same word to every other "Next Up"/"Next up" instance for consistency. "Próximo"/"próximo" (adjective) is kept for the *inline* "Next: X" labels (`widget.inline.next`, `courses.card.nextDue`), a different grammatical role. |
| Standing (widget header and gallery name) | Situación | Matches the L10N-01 spike's own observed Spanish rendering ("Situación") for the same widget, in the same CI run. |
| Insights (tab name, nav title) | Estadísticas | "Perspectivas" was considered and rejected as a literal-but-unnatural calque; "Estadísticas" (statistics) reads naturally for a tab of grade/workload charts. Reviewer may prefer "Información" or "Análisis". |
| Term (the grading period; `insights.trend.range.term*`, `insights.completion.headline/subtitle`) | Período | "Semestre"/"Trimestre" would name a *specific* term length Tally doesn't assume; "Período" stays as generic as the English "term". |
| Needs a look (Insights section header) | Necesita revisión | Literal "Necesita una mirada" was rejected as unnatural; "revisión" (review/check) carries the intended sense. |
| Momentum (Insights card header) | Impulso | Direct, common translation; "Racha" (streak) was rejected for the *section* header because the card's own headline already uses "Racha" for the streak count itself (`insights.streak.days`), and reusing it for the header would read oddly. |
| Grades kept outside Canvas / Course Options menu row (`courseDetail.override.menuRowTitle`, a post-freeze string, PR #42 D17) | Calificaciones fuera de Canvas | Shortened the same way the English was shortened from the full question, for the same truncation reason (iOS menu rows). |
| App Shortcuts: "Refresh Tally" vs. "Update Tally" (two distinct Siri trigger phrases for the same action) | "Actualizar Tally" vs. "Refrescar Tally" | English deliberately offers two different words so Siri matches more phrasings; this pass picked two different Spanish verbs for the same reason, rather than collapsing both to "Actualizar". Reviewer may prefer a different second verb (e.g. "Renovar" was rejected: it means "renew", not "refresh"). |

## Never translated (plan 08 §3.7; unchanged by this pass)

- **"Tally" and "Canvas"** stay exactly as written in every string, including inside Spanish
  sentences (e.g. "Abre Tally para…", "no afiliada a Instructure, Inc."). "Instructure" in the
  legal disclaimer (`account.disclaimer`) also stays as written.
- **Canvas content** (course names and codes, assignment/announcement/event titles,
  assignment-group names, grading-period and term titles, teacher names, letter grades, school
  names) is data from Canvas, passed through `Text(verbatim:)` — nothing to translate, and nothing
  this pass touched.
- **Prices**: only `Product.displayPrice`/`Product.displayName`, which the App Store itself
  localizes; this pass added no hand-formatted price text.

## Copy-honesty notes for the reviewer

- **No new claims.** Every Spanish value says only what the English says. In particular, no
  Spanish string uses "gratis" where the English avoided "free" (owner decision X-1). **Correction
  (L10N-04 round 2, gate-2 verdict T30):** this note previously said the trial strings
  (`subscription.feature.*`, `subscription.paywall.startFreeTrial`) were the *only* "gratis"
  occurrences — inaccurate, found by the gate-2 review. `subscription.locked.body`'s "Tu Tablero
  sigue siendo gratis" also says "gratis", faithfully translating the English "Your Dashboard stays
  free" — so there is no honesty issue, but the claim of "only" was wrong. Every "gratis"
  occurrence translates an English "free" (never a new claim): the trial strings above, and
  `subscription.locked.body`.
- **Legal/subscription text** (`account.disclaimer`, `subscription.paywall.renewal`,
  `subscription.settings.footer*`) keeps every legal fact the English states (the renewal window,
  the revocation of the "free app" framing, etc.) — nothing was summarized or softened.

## Length

Several strings were reworded rather than translated word-for-word, specifically to stay short
(brief: "prefer a shorter faithful Spanish phrasing over a layout change"). Flagged individually in
`docs/pmo/reviews/l10n-04-report.md` under "Length fixes"; the most structurally different one is
`dashboard.greeting` ("Good %1$@, %2$@" → "%1$@, %2$@", with the greeting words
"Buenos días"/"Buenas tardes"/"Buenas noches" now carrying the whole greeting themselves, because
Spanish does not compose a single "Good <word>" stem the way English does across morning/
afternoon/evening).

## Gate-2 round 2 choices (PMO, 2026-10-12): the reviewer should confirm these
- **"Busy" → "Pico"** (`widget.week.busy`, the Week Ahead widget's label under a crowded day). "Ocupado" was truncated to "Oc…" where "Busy" fits. "Pico" follows the Latin American "hora pico" / "día pico".
- **"Subscribe to Canvas Calendar…" → "Agregar calendario de Canvas…"** (`calendar.optionsMenu.subscribe`). "Suscribirse al calendario de Canvas…" was truncated on the smallest iPhone. The action adds Canvas's calendar feed to the Calendar app.
- **The product name stays "Tally Annual"** everywhere on the purchase path (`subscription.locked.title`, `subscription.interstitial.message`), matching the paywall's App Store name.
- **No sentence-final period after a time placeholder** (`notification.*.body`, `widget.answer.*`, `widget.refresh.*`). es-US times end in "p.m.", so "Vence %@." rendered "p.m..".
