# Tally — Go-Live Checklist

The App Store release cannot ship while any **Section A** item is open. **Section B** items are owner reminders for go-to-market.

Status values: `OPEN` · `IN PROGRESS` · `DONE (evidence: …)`. An item is DONE only with evidence linked. A claim alone does not count.

## A. Critical go-live blockers

### GL-01 — Canvas access authorization · `OPEN` · strategy chosen: **both in parallel** (owner, 2026-09-26)
- **What:** Tally's "Sign in with Canvas" only works at a school whose Canvas recognises Tally's app key (`client_id`). Keys come either from each school's Canvas admin, or from Instructure as a *global* key that each school can switch on or off. Asking students to paste a personal token is prohibited by Instructure. Separately, Instructure's API Policy restricts "competitive purposes" and apps that "mirror or replicate" Instructure products.
- **Strategy (owner decision):** pursue **both** routes at once. (a) An Instructure global developer key plus written API-Policy permission via the Partner Program (GTM-02). (b) Per-school keys as individual schools' Canvas admins register Tally. v1 ships an in-app **"Request Tally at my school"** flow and a school-admin setup guide.
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
  3. Publish the privacy policy, the support page and `/.well-known/apple-app-site-association` on the domain. **Drafts are ready in `site/`** (GitHub Pages layout: `CNAME`, `.nojekyll`, `/privacy/`, `/support/`, `/oauth/callback/` fallback, AASA with `webcredentials` + `applinks` for `/oauth/callback`). Fill `__TEAM_ID__`, `__SUPPORT_EMAIL__` and `__EFFECTIVE_DATE__`; the scanner lists them. These are static files; any static host works. The lowest-effort option is **GitHub Pages** with a custom domain (free, automatic HTTPS). `.dev` domains are HTTPS-only by design. Add a `.nojekyll` file so `/.well-known/` is served, and confirm the AASA content type when setting it up. Also set up a support address such as `support@tally-app.dev` (most registrars offer free e-mail forwarding).
  4. Register the bundle ID and App Group in the Apple Developer portal.
  5. Run the script. **Done when it prints `No go-live placeholders remain.`**
  6. Docs are not scanned. Also fill the `[[...]]` fields in `docs/go-to-market/*.md` (`grep -rn '\[\[' docs/go-to-market`).

### GL-03 — Legal review · `OPEN`
- **What:** counsel sign-off before submission on four areas:
  - (1) minors and the state age-assurance laws (Texas SB2420, Utah, Louisiana), and Apple's Declared Age Range API;
  - (2) FERPA posture for a student-directed app;
  - (3) trademark clearance for the name "Tally" (other App Store apps use it);
  - (4) nominative use of "Canvas"/"Instructure" in metadata and the non-affiliation disclaimer, plus review of the privacy-policy text.
- **Draft for review:** `site/privacy/index.html`, marked `DRAFT-PENDING-LEGAL-REVIEW` (the scanner blocks release until the marker is removed after sign-off).
- **Refs:** `docs/pmo/reviews/app-store-compliance.md` D3, D7, R-sections

### GL-04 — App Review sign-in access · `OPEN`
- **What:** Apple's reviewer must be able to use the app without a real student's account.
- **Plan:** use the in-app **"Explore with Sample Data"** mode, powered by the synthetic Canvas dataset in `fixtures/canvas/`. It needs no hosting. Request Apple's prior approval of demo mode (App Review Guideline 2.1) in the review notes.
- **Fallback, only if Apple insists on a live account:** a temporary demo Canvas instance with synthetic data, for the review window only.

### GL-05 — Real-Canvas sign-in validation · `OPEN` (depends on GL-01)
- **What:** on Instructure-hosted Canvas, confirm three things: the public-client token lifetime (the 2-hour window), refresh-token rotation, and whether Canvas re-shows its "Authorize" page on each reconnect. Record the evidence in an ADR.
- **Also (parent linking in v1):** run the observer spike FAM-01 (pairing-code creation with Tally's key, self-registration behaviour, and observer reads of scores and planner). Settle the disputed `observed_user` embedding. Record it in ADR 0002.
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
| GTM-02 | Instructure Partner Program application | Feeds GL-01. Ask for (a) written API-Policy permission, (b) a global developer key enabled broadly, (c) "mobile app" token treatment (BL-13). |
| GTM-03 | Business model | Free, paid, or subscription. Paid features must use Apple In-App Purchase (Guideline 3.1.1). This affects the store listing and paywall design. |
| GTM-04 | Store listing | Name and subtitle without "Canvas" (PMO R11); keywords; description with the non-affiliation disclaimer; screenshots (generated by CI in sample-data mode); age-rating questionnaire; privacy label ("Data Not Collected" as designed); accessibility nutrition labels. |
| GTM-05 | Support operations | Support email, `SECURITY.md` vulnerability-disclosure contact, response targets. |
| GTM-06 | Paid Apps Agreement, banking and tax, **App Store Small Business Program** enrolment (15% commission from day one). Create **two** subscription groups: "Tally Annual" $9.99/yr (1-month trial) and "Tally Parent" $4.99/yr. Family Sharing off; multiseat on (P6). | Must be done **before the first sale**. Depends on GTM-01. See PRD §11.1 and `docs/pmo/reviews/pricing-licensing.md`. |
| GTM-07 | Terms of Use (EULA) link and subscription disclosure copy | Apple's standard EULA or your own. The paywall must link to it and to the Privacy Policy (PRD §11.3; Guideline 3.1.2). |
