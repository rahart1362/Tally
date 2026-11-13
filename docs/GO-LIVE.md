# Tally — Go-Live Checklist

The App Store release cannot ship while any **Section A** item is open. **Section B** items are owner reminders for go-to-market.

Status values: `OPEN` · `IN PROGRESS` · `DONE (evidence: …)`. An item is DONE only with evidence linked. A claim alone does not count.

## A. Critical go-live blockers

### GL-01 — Canvas access authorization · `OPEN` · strategy chosen: **both in parallel** (owner, 2026-09-26)
- **What:** Tally's "Sign in with Canvas" only works at a school whose Canvas recognises Tally's app key (`client_id`). Keys come either from each school's Canvas admin, or from Instructure as a *global* key that each school can switch on or off. Asking students to paste a personal token is prohibited by Instructure. Separately, Instructure's API Policy restricts "competitive purposes" and apps that "mirror or replicate" Instructure products.
- **Strategy (owner decision):** pursue **both** routes at once. (a) An Instructure global developer key plus written API-Policy permission via the Partner Program (GTM-02). (b) Per-school keys as individual schools' Canvas admins register Tally. v1 ships an in-app **"Request Tally at my school"** flow and a school-admin setup guide.
- **Key requirements (local live testing, #98/#100/#101):** whichever route issues it, the key must be a **public client** (PKCE, no client secret) flagged as a **mobile app**, scoped to exactly Tally's 8 scopes (`CanvasScopes.tally`, `packages/TallyCore/Sources/TallyCanvasAPI/Client/CanvasEndpoints.swift` -- least privilege, owner decision 2026-11-03: v1 does not request the family scope; it returns with M4 parent linking). Why:
  - Canvas only accepts a no-secret (PKCE) token exchange for a developer key whose `client_type` is `public`; a confidential key gets `invalid_client`.
  - As of canvas-lms `1c9f0bb` (2026-04-30), the developer-keys API — and so every admin UI built on it — has no field to set `client_type`. Route (b) schools cannot self-serve this: they must ask their Canvas host (for most schools, Instructure Support) to set it server-side.
  - A **mobile-app** public key gets 90-day sessions; a public key with no mobile-app flag gets only a 2-hour rolling window (GL-05).
- **Drafts ready:** `docs/go-to-market/instructure-partner-request.md` (route a; the owner sends it) · `docs/go-to-market/school-admin-setup-guide.md` (route b).
- **Done when:** Instructure's written permission is on file **and** at least one key (global or school) works on real Canvas (GL-05).
- **Engineering impact:** none on the build. The app is identical either way; only the key configuration differs. Development and testing use sample data and a locally run open-source Canvas.
- **Refs:** `docs/pmo/02-program-plan.md` §0, §6 · `docs/pmo/reviews/security.md` D1, D2, D4

### GL-02 — Owned domain and app identity · `IN PROGRESS` · domain **tally-app.dev** registered 2026-09-26
- **What:** a domain the owner controls. It sets the permanent bundle ID (`dev.tally-app.tally`), the App Group, the HTTPS sign-in callback (universal link), and the URLs of the privacy-policy and support pages, which App Store Connect requires.
- **Where the placeholders are — the only file to edit:** `apps/TallyiOS/Config/Identity.xcconfig`

  | Setting | Value | Status |
  |---|---|---|
  | `TALLY_ORG_DOMAIN` | `tally-app.dev` | ✅ set |
  | `TALLY_BUNDLE_ID_PREFIX` | `dev.tally-app` → bundle ID `dev.tally-app.tally`, App Group `group.dev.tally-app.tally` | ✅ set (changeable until the first TestFlight upload) |
  | `DEVELOPMENT_TEAM` | *(empty)* | ⏳ needs your Apple Team ID (after GTM-01) |

  Bundle ID, App Group, Info.plist keys (`CFBundleIdentifier`, `TallyOrgDomain`, `TallyAppGroupID`) and all runtime URLs derive from these three values.
- **Find every remaining placeholder** (use this, not line numbers in this doc, which drift):
  ```bash
  scripts/go-live/find-placeholders.sh
  ```
  It lists `file:line` for (1) tagged placeholders, (2) placeholder domain values, and (3) legacy hard-coded identifiers (`com.tally…`, the `"tally"` URL scheme) left from the prior build. Those legacy lines are removed by the M1/M2 rewrite (ASC-01), which derives every identifier from the bundle ID. The release gate runs this script and **fails while anything is listed**.
- **Remaining steps:**
  1. ~~Register the domain.~~ Done (tally-app.dev).
  2. Set the Team ID above (after enrolling, GTM-01).
  3. Publish the privacy policy, the terms, the security page, the support page and `/.well-known/apple-app-site-association` on the domain. **Drafts are ready in `site/`** (GitHub Pages layout: `CNAME`, `.nojekyll`, `/privacy/`, `/terms/`, `/security/`, `/support/`, `/oauth/callback/` fallback, `404.html` as the same fallback for every other path, AASA with `webcredentials`, `/.well-known/security.txt`). Fill `__TEAM_ID__`, `__SUPPORT_EMAIL__`, `__SECURITY_EMAIL__` (the security mailbox — `site/security/index.html` and `/.well-known/security.txt`), `__GOVERNING_LAW__` (`site/terms/index.html`) and `__EFFECTIVE_DATE__`; the scanner lists them. These are static files; any static host works.

     **Correction (2026-10-25): merging `site/` to `main` does not publish or host anything.** `tally-app.dev` has no DNS record and GitHub Pages is not enabled (confirmed: the Pages API returns 404) — the drafts merged in PR #87 and PR #90 are not live, including the Privacy and Terms text. Publishing is this step, and it is the owner's to do. The lowest-effort option is **GitHub Pages** with a custom domain (free, automatic HTTPS), but `site/` is **not** a Pages source folder by itself: Pages serves the repo root or `/docs` on a chosen branch, so this needs either a workflow that publishes `site/`'s contents to that location (or to a `gh-pages` branch / Pages build artifact), or another static host. `.dev` domains are HTTPS-only by design. Add a `.nojekyll` file so `/.well-known/` is served, and confirm the AASA content type when setting it up. Also set up a support address such as `support@tally-app.dev` (most registrars offer free e-mail forwarding). SEC1-05: the real redirect is now per-institution, `/oauth/callback/<institutionId>` (`SignInHandoffViewModel.redirectURI(forHost:)`) — `applinks` is not needed for it, and was never added: `ASWebAuthenticationSession`'s `.https(host:path:)` callback only requires the `webcredentials` domain association (verified against Apple's documented contract, security.md's citation table), whichever path a session is started with.

     **Pre-submission blocker:** the Privacy and Terms URLs must load before App Store submission, since nothing is hosted yet.
  4. Register the bundle ID and App Group in the Apple Developer portal.
  5. Run the script. **Done when it prints `No go-live placeholders remain.`**
  6. Docs are not scanned. Also fill the `[[...]]` fields in `docs/go-to-market/*.md` (`grep -rn '\[\[' docs/go-to-market`).

### GL-03 — Legal review · `DONE (owner sign-off, 2026-11-12)`
- **What:** counsel sign-off before submission on four areas:
  - (1) minors and the state age-assurance laws (Texas SB2420, Utah, Louisiana), and Apple's Declared Age Range API;
  - (2) FERPA posture for a student-directed app;
  - (3) trademark clearance for the name "Tally" (other App Store apps use it);
  - (4) nominative use of "Canvas"/"Instructure" in metadata and the non-affiliation disclaimer, plus review of the privacy-policy text.
- **Outcome (2026-11-12):** the owner reviewed the privacy, terms and security pages and the four areas above and signed off; the `DRAFT-PENDING-LEGAL-REVIEW` banners are removed. Re-check the state age-assurance laws' status shortly before launch, and revisit this item before school sales or a trademark filing.
- **Refs:** `docs/pmo/reviews/app-store-compliance.md` D3, D7, R-sections

### GL-04 — App Review sign-in access · `OPEN`
- **What:** Apple's reviewer must be able to use the app without a real student's account.
- **Plan:** use the in-app **"Explore with Sample Data"** mode, powered by the synthetic Canvas dataset in `fixtures/canvas/`. It needs no hosting. Request Apple's prior approval of demo mode (App Review Guideline 2.1) in the review notes.
- **Fallback, only if Apple insists on a live account:** a temporary demo Canvas instance with synthetic data, for the review window only.

### GL-05 — Real-Canvas sign-in validation · `OPEN` (depends on GL-01)
- **What:** on Instructure-hosted Canvas, confirm three things: the public-client token lifetime (the 2-hour window), refresh-token rotation, and whether Canvas re-shows its "Authorize" page on each reconnect. Record the evidence in an ADR.
- **Also (parent linking in v1):** run the observer spike FAM-01 (pairing-code creation with Tally's key, self-registration behaviour, and observer reads of scores and planner). Settle the disputed `observed_user` embedding. Record it in ADR 0002.
- **FAM-01 / M4 note:** parent pairing-code creation and redemption need the school's Canvas login self-registration turned on (`observer_pairing_codes_api_controller.rb:61`) — confirmed live (#101). Without it, family linking fails at that school regardless of which scopes the key grants.
- **Provisional answers from a locally run open-source Canvas (2026-10-28)** — still need Instructure-hosted confirmation before this item can close:
  - a non-mobile public key's session is a 2-hour **rolling** window; a mobile-app public key's is 90 days. The token response's `expires_in` is only a hint, not the real lifetime.
  - refresh tokens **rotate** on every use; the old one is invalid immediately (`invalid_grant`).
  - Canvas re-shows its consent/"Authorize" page on every sign-in unless the developer key is marked `trusted` (Rails-console only; not available to a school admin).
  - a school turning Tally off via its account binding is now detected (#101): a fresh token rejected again, or an authorize redirect's `error=unauthorized_client`.
- **Refs:** ADR 0001 · security.md WP-SEC-17

### GL-06 — Release gate green · `OPEN`
- **What:** `release-gate.yml` passes on the release commit. It covers:
  - Xcode 26+ Release build
  - critical-flow UI tests (kit 13)
  - accessibility audit with 0 unwaived issues
  - opaque 1024 icon
  - `PrivacyInfo.xcprivacy` and Info.plist checks
  - `ITSAppUsesNonExemptEncryption = NO`, with only Apple crypto linked
  - **`find-placeholders.sh` clean**
  - App Store screenshots generated
- **Refs:** program plan M5

## B. Go-to-market reminders (owner, when ready)

| ID | Reminder | Notes |
|---|---|---|
| GTM-01 | **Apple Developer account type: Individual vs Organization** | Individual: your legal name is the seller, and for EU trader status your personal contact details are published. Organization: needs a legal entity (e.g. an LLC) and a **D-U-N-S number, which takes days to weeks**, so start early. Also decide whether to launch on EU storefronts (Digital Services Act trader details). |
| GTM-02 | Instructure Partner Program application | Feeds GL-01. Ask for (a) written API-Policy permission, (b) a global developer key enabled broadly, (c) "mobile app" token treatment (BL-13), (d) public client type, (e) Tally's 8 scopes (`CanvasScopes.tally`; v1 excludes the family scope, owner decision 2026-11-03). |
| GTM-03 | Business model | Free, paid, or subscription. Paid features must use Apple In-App Purchase (Guideline 3.1.1). This affects the store listing and paywall design. |
| GTM-04 | Store listing | Name and subtitle without "Canvas" (PMO R11); keywords; description with the non-affiliation disclaimer; screenshots (generated by CI in sample-data mode); age-rating questionnaire; privacy label ("Data Not Collected" as designed); accessibility nutrition labels. |
| GTM-05 | Support operations | Support email, `SECURITY.md` vulnerability-disclosure contact, response targets. |
| GTM-06 | Paid Apps Agreement, banking and tax, **App Store Small Business Program** enrolment (15% commission from day one). Create **two** subscription groups: "Tally Annual" $9.99/yr (1-month trial) and "Tally Parent" $4.99/yr. Family Sharing off; multiseat on (P6). | Must be done **before the first sale**. Depends on GTM-01. See PRD §11.1 and `docs/pmo/reviews/pricing-licensing.md`. |
| GTM-07 | Terms of Use (EULA) link and subscription disclosure copy | Apple's standard EULA or your own. The paywall must link to it and to the Privacy Policy (PRD §11.3; Guideline 3.1.2). |
