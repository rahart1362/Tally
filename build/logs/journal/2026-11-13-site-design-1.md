# 2026-11-13 SITE-DESIGN-1 journal

- Audited `main` @ ce16aee with wrangler dev + Playwright (Chromium 1280/1440, WebKit iPhone SE/15/15 Pro Max/iPad, 200% zoom reflow; light and dark): 140 cases, 12 overflow cases (admin, terms, support), 7 pages without shared chrome, no web fonts.
- Replaced `_style.css` with one `assets/site.css`; rebuilt the 7 legal/support/admin/404/callback pages and the sent page around a shared header/footer, with self-hosted DM Serif Display, Inter and JetBrains Mono (94,168 bytes, OFL licences included).
- Found two causes only the measurements showed: grid tracks sized by `<input>` intrinsic width, and a WebKit `<select>` widening the page; fixed with `minmax(0,1fr)` and `overflow:hidden` on the select.
- Verified: 0/140 overflow after, 0 console/CSP errors, visible `<main>` text identical on all 10 pages, POLICY-FLOWS block and all comments byte-identical, `.well-known` files byte-identical, contact tests 11/11, dry-run deploy OK.
