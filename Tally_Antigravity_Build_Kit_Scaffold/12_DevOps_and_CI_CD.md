# DevOps and CI/CD

## Standards
- trunk-based development or short-lived branches
- pull request template
- automated lint/build/test
- code review required for non-trivial changes
- ADRs for architecture changes
- semantic versioning

## Suggested Tooling
- GitHub Actions
- Fastlane
- SwiftLint
- SwiftFormat
- XCTest / XCUITest
- optional Danger or review bot

## CI Pipeline Stages
1. lint
2. build
3. unit tests
4. UI smoke tests
5. security/dependency scan
6. artifact/report generation
