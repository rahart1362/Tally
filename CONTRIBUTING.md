# Contributing

Use small commits, run lint/tests, and update build state files after each task.

## Code review checklist

Check every change against these rules. CI enforces the ones marked **(gate)**.

- **Navigation containers are roots only.** `TabView` and `NavigationStack` appear only as a
  root (a `RootView` route, a sheet's content) or as a tab's root inside the root `TabView`. Never
  push a view that contains a `TabView` or a `NavigationStack` through `navigationDestination`:
  such a push never renders (2d3131f's bisect, perf-app-runtime.md §1.2). The Home shell is
  constructed only in `RootView.swift` **(gate: hygiene)**, and the sample-data UI tests assert
  that entering sample data removes Welcome from the hierarchy.
- **No debug logging, `Task.detached` or unaudited concurrency flags** in shipping code
  **(gate: hygiene)**. Use a `@concurrent` function or an actor for off-main work.
- **No force unwraps, `try!`, `as!` or implicitly unwrapped optionals** in shipping code
  **(gate: lint)**. A provably safe exception carries `// swiftlint:disable:this <rule>` and the
  reason on the same line.
