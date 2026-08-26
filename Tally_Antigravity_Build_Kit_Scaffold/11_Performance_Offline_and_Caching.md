# Performance, Offline, and Caching

## UX Targets
- warm start from cache: near-instant / under 300ms target
- primary screen interactions: imperceptibly fast
- manual refresh feedback visible immediately

## Cache Strategy
- Store latest successful payload only, replacing prior cache atomically
- Maintain refresh metadata separately:
  - `last_successful_refresh_at`
  - `last_attempted_refresh_at`
  - `last_refresh_source`
  - `cache_is_stale`
- Clear breadcrumb once fresh data arrives

## Offline Behavior
- App remains fully browsable from cache
- Stale badge/breadcrumb is visible but subtle
- Manual refresh retried when connectivity improves

## Suggested UI Copy
- Fresh: `Updated just now`
- Live delayed: `Live refresh is taking longer than expected — showing saved data from 2:14 PM.`
- Offline: `You’re offline — showing your latest saved data.`
