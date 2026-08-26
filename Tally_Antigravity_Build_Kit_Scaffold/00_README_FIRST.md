# Tally – Antigravity Build Kit

This package contains:
- end-to-end product requirements
- system architecture and wiring guidance
- repository scaffolding for a native iOS build
- an agentic execution protocol for Antigravity
- manifest/checkpoint/logging conventions to reduce drift and hallucination
- the latest 3 visual assets for Tally

## What Tally Is
Tally is a privacy-first iOS app that helps students see all Canvas courses, current grades, trends, alerts, and schedule information in a premium mobile experience. It is designed to feel instant, reliable, and usable even when Canvas is slow or temporarily unavailable.

## Key Product Principles
1. **Canvas-first and student-owned** – authentication uses the student’s own Canvas credentials.
2. **No Tally account** – no separate Tally identity, no server-side user profile required.
3. **No server-side retention of Canvas data** – Tally does not persist student Canvas data in its own backend.
4. **Local-first reliability** – the app uses encrypted on-device caching so the app is always useful.
5. **Fast by design** – every user interaction should feel effectively instant.
6. **Enterprise-grade engineering discipline** – clean architecture, modularity, testing, observability, automation.

## Recommended Build Approach
- Native iOS app built with **SwiftUI + Swift Concurrency + Swift Package Manager**
- Local cache with **encrypted SQLite/Core Data wrapper**
- Secure token storage in **Apple Keychain**
- Canvas auth using **OAuth 2.0 Authorization Code + PKCE**
- Optional integrations with Apple, Microsoft 365, and Google using device-side OAuth and native frameworks
- No Tally cloud required for core app functionality

## How Antigravity Should Use This Package
1. Read `01_Product_Requirements.md`
2. Read `02_System_Architecture.md`
3. Read `03_Repo_Scaffold_Tree.md`
4. Read `04_Agentic_Build_Protocol.md`
5. Read `05_Execution_Manifest.yaml`
6. Build in small increments and update status under `repo-template/build/`

## Important Product Constraint
Tally may cache the latest Canvas retrieval **on-device only** in order to remain usable offline or when refresh is delayed. Cached data replaces the older cache, and the UI must clearly show:
- **Last refreshed timestamp**
- **Manual refresh icon/action**
- **Subtle stale-data breadcrumb** when live refresh exceeds 10 seconds and cached data is being shown
