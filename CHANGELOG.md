# Changelog

## 0.1.0 — 2026-09-20

Initial release of Refresher, a standalone UIKit pull-to-refresh and pagination package for iOS 16+ with no third-party dependencies. Requires Swift 6 tooling and uses Swift 5 language mode.

### Features

- One `RefreshController` coordinates async refresh and pagination operations. Use either capability independently or both together.
- Pull gestures, programmatic refresh, explicit page requests and automatic pagination near the bottom, including filling short content.
- Refresh supersedes pagination; cancellation and operation identities prevent stale completions from changing controller state.
- Automatic pagination stops after errors or a page that does not increase content height, with a fresh drag or explicit request allowing another attempt.
- Combine state observation with synchronous MainActor delivery and ordered reentrant commands.
- Custom `RefreshHeader` and `LoadMoreFooter` views, default system-colored indicators, and configurable heights, preload distance and closing duration.
- Additive inset handling without replacing the scroll view delegate, plus explicit cancellation, data-session reset and synchronous detach.
- A runnable table/grid example and simulator test scripts.

### Validation

- 32 Swift Testing tests and 5 XCUITest tests passed with Xcode 27.0 on iOS 27.0 simulators.
- Two additional UI probes confirmed retrying pagination-only short content after a failure.
- iOS 16 is the deployment target; iOS 16 runtime and physical-device behavior were not verified.

### Integration notes

- Retain the controller and call `contentDidChange()` after mounting or an external layout transaction when needed.
- Async operations must check cancellation before committing data and await their own list updates. Refresher cannot undo writes made by a cancellation-ignoring closure.
- Call `detach()` before removing or replacing the component on a scroll view that remains alive.
