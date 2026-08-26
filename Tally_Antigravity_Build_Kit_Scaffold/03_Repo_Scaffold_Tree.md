# Repository Scaffold Tree

```text
Tally/
├── apps/
│   └── TallyiOS/
│       ├── TallyApp.xcodeproj
│       ├── TallyApp/
│       │   ├── App/
│       │   ├── Navigation/
│       │   ├── Resources/
│       │   ├── Features/
│       │   │   ├── Dashboard/
│       │   │   ├── Courses/
│       │   │   ├── CourseDetail/
│       │   │   ├── Calendar/
│       │   │   ├── Todo/
│       │   │   ├── Insights/
│       │   │   └── Settings/
│       │   └── Supporting/
│       └── TallyAppUITests/
├── packages/
│   ├── TallyAppFeature/
│   ├── TallyDesignSystem/
│   ├── TallyDomain/
│   ├── TallyData/
│   ├── TallyCanvasKit/
│   ├── TallyCalendarSync/
│   ├── TallyNotifications/
│   ├── TallyCache/
│   ├── TallyObservability/
│   ├── TallySecurity/
│   └── TallyTestingKit/
├── docs/
│   ├── architecture/
│   ├── adrs/
│   ├── api/
│   ├── ux/
│   └── runbooks/
├── build/
│   ├── state/
│   ├── logs/
│   ├── checkpoints/
│   └── decisions/
├── scripts/
├── .github/
│   └── workflows/
├── fastlane/
├── Package.swift
├── README.md
├── AGENT_GUIDE.md
├── CONTRIBUTING.md
├── SECURITY.md
├── PRIVACY.md
├── CHANGELOG.md
└── Makefile
```

## Suggested Responsibility by Package
- **TallyDesignSystem**: colors, typography, spacing, reusable UI, icons, chart wrappers
- **TallyDomain**: entities, value objects, use cases, reminder rules, grade engines
- **TallyData**: repositories and local persistence orchestration
- **TallyCanvasKit**: Canvas API/auth client and DTO mappings
- **TallyCalendarSync**: Apple, Microsoft, and Google calendar sync adapters
- **TallyNotifications**: reminder engine and local notification orchestration
- **TallyCache**: encrypted cache store, freshness rules, atomic replace logic
- **TallyObservability**: logger facade, event IDs, timing metrics, diagnostics
- **TallySecurity**: Keychain access, token lifecycle, privacy utilities
- **TallyTestingKit**: mocks, stubs, fixtures, snapshot helpers
