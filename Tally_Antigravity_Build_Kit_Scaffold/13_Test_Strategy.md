# Test Strategy

## Test Types
- unit tests for domain/use cases
- integration tests for repositories and adapters
- contract tests for API mapping
- UI tests for navigation and critical flows
- performance tests for cache load and refresh orchestration
- accessibility checks for VoiceOver labels and Dynamic Type

## Critical Scenarios
- first login
- app launch with valid cache
- app launch with no cache
- refresh succeeds under 10 seconds
- refresh exceeds 10 seconds and cache is shown
- refresh succeeds after timeout and UI self-heals
- threshold alerts fire correctly
- notifications obey quiet hours
- Microsoft/Google sync permissions denied
