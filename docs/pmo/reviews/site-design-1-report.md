# SITE-DESIGN-1 report: tally-app.dev design pass

Scope: presentation only. One stylesheet (`site/assets/site.css`), shared header/footer on all 10 pages, self-hosted fonts (94,168 bytes, OFL), an admin scope table that stacks on phones, iOS/WebKit hygiene, HSTS in `site/_headers`. `site/_style.css` is removed.

Evidence (local, Playwright on Linux; not a real iPhone):
- Before: 140 page x viewport x theme cases, 12 with horizontal overflow (admin, terms, support). After: 0.
- Console errors and CSP violations after: 0 (the 404 page's own status note excepted).
- Visible text of each page's `<main>` before vs after: identical on all 10 pages (script diff). The old inline footer links on admin, security and terms are replaced by the shared footer.
- POLICY-FLOWS block and every other HTML comment in the legal pages: byte-identical; `check_policy_matches_app.py` passes. AASA and `security.txt` byte-identical.
- No ledger row added to `docs/release/significant-change-log.md`: the POLICY-FLOWS block is unchanged, so the checklist does not call for one (visual-only change).

Open items: real-device iPhone Safari check by the owner; proposals for wording are in the PR body.
