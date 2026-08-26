# System Architecture – Tally

## 1. Architecture Style
Use a modular **Clean Architecture** / **Hexagonal Architecture** design:
- Presentation layer: SwiftUI views, navigation, view models
- Domain layer: use cases, policies, reminder rules, grade calculations
- Data layer: repositories, local cache, remote clients, adapters
- Integration layer: Canvas, Apple, Microsoft, Google providers
- Cross-cutting: security, observability, feature flags, configuration, testing

## 2. Recommended Technical Stack
- Language: Swift 6+
- UI: SwiftUI
- Async: Swift Concurrency (`async/await`)
- Dependency management: Swift Package Manager
- Persistence: SQLite-backed local store or Core Data wrapper with encryption strategy
- Networking: URLSession + typed API client
- Auth: OAuth 2.0 PKCE
- Secure secrets/tokens: Keychain
- Logging: OSLog + structured app logger facade
- Testing: XCTest + XCUITest
- CI/CD: GitHub Actions + Fastlane
- Quality: SwiftLint + SwiftFormat

## 3. Major Modules
### Presentation
- Dashboard feature
- Courses feature
- Course detail feature
- Calendar feature
- To-do feature
- Insights feature
- Settings feature

### Domain
- Course aggregation
- Grade calculation and normalization
- Trend analysis
- Alert rules
- Reminder scheduling
- Cache freshness policy
- Change-digest engine
- What-if grade simulator

### Data
- Canvas repository
- Local cache repository
- User preferences repository
- Sync state repository
- Attachment metadata repository

### Integrations
- Canvas API client
- Apple calendar/reminder adapter
- Microsoft 365 adapter
- Google adapter
- Attachment opener/router

### Platform Services
- Refresh orchestrator
- Background app refresh scheduler
- Local notification scheduler
- Cache expiration manager
- Telemetry / health reporter (non-sensitive)

## 4. Sync & Cache Flow
1. App launches.
2. Read local cache instantly.
3. Render UI from cache.
4. Trigger live refresh in background.
5. If live refresh succeeds within 10 seconds:
   - update repositories
   - atomically replace cache
   - update UI and last refreshed label
6. If live refresh exceeds 10 seconds:
   - keep showing cache
   - show subtle breadcrumb: “Live refresh delayed — showing saved data from <timestamp>.”
   - continue refresh in background if allowed
7. When refresh eventually succeeds:
   - replace cache
   - update diff/change digest
   - clear stale-data breadcrumb

## 5. Identity, Security, and Privacy Model
- No Tally account or proprietary identity provider
- Student authenticates directly to Canvas
- Access tokens stored only in Keychain
- Canvas data persisted only as encrypted local cache on device
- Microsoft/Google integrations are optional and use separate device-side authorization grants
- Sensitive payloads never logged

## 6. Integration Wiring
### Canvas
- Auth: OAuth 2.0 + PKCE
- Data pulled: courses, assignments, submissions, due dates, grades, calendar items, announcements where useful
- Sync: launch, manual refresh, background refresh, hourly check-in target

### Apple
- EventKit for calendar sync
- UserNotifications for local reminders
- WidgetKit for glanceable widgets
- App Intents/Shortcuts
- QuickLook/document opening

### Microsoft 365
- Device-side OAuth for Outlook calendar/mail access
- Calendar mirror or selective export
- Attachment open routing to Office apps

### Google
- Device-side OAuth for Calendar/Gmail/Drive access
- Calendar mirror or selective export
- Attachment open routing to Google apps

## 7. Performance Design Choices
- read-through cache
- background refresh orchestration
- optimistic rendering from local data
- fine-grained diffing to update only changed view state
- lightweight domain models
- precomputed dashboard aggregates
- pagination and lazy load for large course/assignment sets
