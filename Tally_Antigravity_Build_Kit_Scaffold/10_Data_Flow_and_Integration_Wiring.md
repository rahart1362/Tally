# Data Flow and Integration Wiring

## Core Flow
1. User opens app.
2. Local cache loads immediately.
3. Refresh orchestrator launches background pull from Canvas.
4. Domain layer computes aggregates/trends.
5. UI updates.
6. Notification engine re-evaluates rules after data changes.
7. Optional sync/export adapters mirror data to Apple/Microsoft/Google.

## Attachment Handling
- Prefer opening attachments in-place using iOS-native mechanisms.
- Route to Office or Google apps when appropriate and available.
- Never copy attachment metadata into server-side systems.

## Refresh Policy
- Auto on app launch
- Auto hourly check-in if app/background policy permits
- Manual force refresh from UI
- Time budget: 10 seconds
- On timeout: show saved cache + stale-data breadcrumb
