# Tally — Backlog (future enhancements, not in v1)

Items move from here into the program plan (`docs/pmo/02-program-plan.md`) only by an owner decision.
v1 scope is the kit's PRD minus what is listed here.

| ID | Enhancement | Origin | Why deferred | Revisit when | Design notes |
|---|---|---|---|---|---|
| **BL-01** | **Stateless token-exchange broker** for long-lived Canvas sessions (confidential client; stores no Canvas data) | Owner O2, 2026-09-26 | Owner wants no hosted services. v1 uses PKCE-only per-launch handshake (ADR 0001). | Real-Canvas evidence (GL-05) shows re-sign-in is too disruptive **and** BL-13 is unavailable | security.md §3.1 option B; `ClientRegistration.clientType` keeps it a config switch. Changes the privacy label and needs an uptime target and App Attest. |
| **BL-02** | **Microsoft 365**: Outlook calendar and mail via Microsoft Graph, attachments to Office apps | Owner O3 | v1 coverage: iOS Calendar already writes to Outlook accounts added in Settings; Mail compose sheet; ICS subscription; share sheet / open-in for attachments. Avoids MSAL, publisher verification and school-tenant consent blocks. | After v1 launch, if users ask for more than v1 covers | **Owner condition:** Canvas's own sign-in stays the only way to log in to Tally. Microsoft/Google are optional add-ons, never a login method. |
| **BL-03** | **Google Workspace**: Google Calendar, Gmail and Drive via Google APIs | Owner O3 | As BL-02. Gmail/Drive scopes are "restricted" and need Google's security assessment (CASA). | As BL-02 | Same owner condition as BL-02. |
| BL-04 | Full two-way Apple Calendar sync (EventKit full access, study blocks, de-duplicated) | PMO R6 | v1 uses a Canvas ICS subscription plus per-item "Add to Calendar", which needs no permission prompt. | When the study-plan generator writes study blocks | architecture.md §3.4 reconciler with stable `tally://` keys. |
| BL-05 | Multi-account switcher (dual enrolment, two schools) | PMO R8 | Single active account in v1; storage is already account-scoped. | User demand | UI-only follow-up; no migration. |
| BL-06 | "Vault mode": Secure Enclave-bound cache key requiring user presence | encryption.md D-E5 | Blocks background refresh and widgets; the v1 app lock covers the UI. | Security-sensitive user segment requests it | encryption.md §3. |
| BL-07 | iPad multi-column layout | Kit 06, PMO R4 | v1 is iPhone-only. | After v1 | — |
| BL-08 | watchOS companion glance app | Kit 06 | Scope. | After v1 | Reuses the glance projection. |
| BL-09 | Lock-screen Live Activity for the next due item | Kit 06 | Scope. | After v1 | Must respect notification privacy rules (R10). |
| BL-10 | Semester planning wizard | Kit 06 | Scope. | After v1 | — |
| BL-11 | Student academic goals and coach recommendations | Kit 06 | Scope. | After v1 | — |
| BL-12 | Canvas GraphQL adapter for very large accounts | architecture.md §3.3 | REST is sufficient for v1. | Performance test shows large accounts over the 10 s budget | `CanvasGateway` protocol already allows it. |
| **BL-13** | Longer Canvas sessions via Instructure's "mobile app" token treatment (≈90-day refresh) | security.md D4 | Needs Instructure's cooperation; requested as part of GL-01. | GL-01 conversation with Instructure | Removes most per-launch re-sign-ins without any server. |
| **BL-14** | **SMS and e-mail reminder channels** (push notifications first in v1) | Owner O9 | iOS cannot send SMS or e-mail in the background without a server. The only no-hosting options are user-initiated compose sheets. Automatic delivery needs an external messaging service, which conflicts with the no-hosting preference. | After v1; the options analysis is in `docs/pmo/ux/insights-at-a-glance.md` §4 | PRD §7 already marks outbound e-mail as "optional / best-effort". |
| BL-15 | School-paid licences (institution buys access for its students) | Pricing review §11.8 | Apple subscriptions can't be bought in volume, and offer codes may not be sold. Needs Apple's Volume Purchase / Apple School Manager route or an out-of-app contract. | A school asks to pay | `docs/pmo/reviews/pricing-licensing.md` |
| BL-16 | Monthly plan | Pricing review §11.8 | One annual plan keeps the paywall simple; students' year maps to terms. | Price-review data (PRD §11.7) | — |
| BL-17 | Promotional offers (signed, server-generated) | Pricing review §11.5 | Requires a server signature; the owner wants no hosting. Offer codes and win-back offers cover v1. | Only if a server ever exists (BL-01) | — |
