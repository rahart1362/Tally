# Logging and Observability

## Goals
Provide sufficient internal diagnostics without leaking student-sensitive data.

## Logging Standards
- Use structured logs with event IDs
- Avoid logging student names, grades, assignment titles, or raw API payloads
- Log timings, counts, statuses, and error categories instead
- Use separate levels: debug, info, warning, error, fault

## Example Event IDs
- AUTH-1001 Canvas login started
- AUTH-1002 Canvas login succeeded
- SYNC-2001 Cache load started
- SYNC-2002 Cache load completed
- SYNC-2003 Live refresh started
- SYNC-2004 Live refresh timed out; cache displayed
- SYNC-2005 Live refresh succeeded
- NOTIF-3001 Reminder scheduled
- NOTIF-3002 Reminder suppressed due to quiet hours
- PERF-4001 App launch warm start duration

## Agent Build Logs
Antigravity should append iteration logs to:
- `build/logs/iteration_journal.md`
- `build/state/current_status.json`
