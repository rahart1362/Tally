# DRAFT — Instructure Partner Program request (owner sends; not sent by the team)

Supports GO-LIVE **GL-01** (route a) and **GTM-02**. Fill the `[[...]]` fields before sending.
Suggested channel: the Instructure Partner Program application (Integrated tier) at instructure.com/partners, plus a direct e-mail to the partnerships contact they assign.

---

**Subject:** Partnership request: Tally, a privacy-first student companion app for Canvas (global developer key and API Policy permission)

Hello Instructure Partnerships team,

I'm [[Owner name]], [[title]] of [[Company or "an independent developer"]]. I'm building **Tally**, a native iOS app that helps students *plan around* their Canvas coursework. It gives them an at-a-glance view of grades and upcoming deadlines, what changed since they last checked, and reminders they control. Every submission, discussion and course action stays in Canvas: Tally deep-links back to Canvas for those.

**How Tally treats Canvas data (the part we care most about)**
- The student signs in directly with their school's Canvas using OAuth 2.0 **Authorization Code + PKCE** (public client). Tally never sees the student's password.
- **Tally has no server and no Tally account.** Canvas data goes only from the institution's Canvas to the student's own iPhone. It is never sent to, stored on, or processed by anything Tally operates.
- The on-device copy is encrypted, replaced on every refresh, and erased on sign-out. Sign-out also revokes the token through `DELETE /login/oauth2/token`.
- Read-only access to about eight endpoints: profile, courses with scores, assignment groups with submissions, grading periods, planner items, calendar events, announcements and user colours. There is no write access.
- No ads, no analytics SDKs, no data sale.

**What we're asking for**
1. **Written confirmation that Tally is a permitted use under the Canvas API Policy.** In particular, we want to confirm how the "competitive purposes" and "mirror or replicate" clauses apply. Tally complements Canvas Student and does not replace it: it is a planning and reminder layer that links back into Canvas for every action. We are happy to adjust positioning or features to stay clearly within policy.
2. **A global developer key for Tally.** It would be a public (PKCE) API key with the scopes above, so that students at participating institutions can connect without each school creating its own key. We'd welcome guidance on how it is enabled by default and how institutions can opt out.
3. **Mobile-app token treatment for that key** (longer refresh-token lifetime), so students aren't asked to sign in again after short idle periods.
4. **Partner Program enrolment** at the tier you recommend, including sandbox access for integration testing.

We'd be glad to share our security and privacy documentation, threat model and architecture decision records. We can also demo a build on request.

Thank you,
[[Owner name]] · [[email]] · https://tally-app.dev

---
*Internal notes (remove before sending):*
- Evidence behind the asks: `docs/pmo/reviews/security.md` D1/D4, `docs/adr/0001-canvas-sign-in-launch-handshake.md`, and program plan §6 (API Policy clauses verified 2026-09-26).
- Do not claim affiliation or endorsement anywhere (PMO R11).
