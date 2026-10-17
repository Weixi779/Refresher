# Changelog

## 0.3.0 — 2026-10-17

- Retain and coalesce forced refreshes across inactive periods and failed requests.
- Coordinate native return-to-top with refresh completion and content replacement.
- Support stable refresh origins for collapsible headers and clip indicators below chrome.
- Wait for reveal completion, support an optional completion pause, and release waits on interruption.
- Hide exhausted footers and remove their owned inset.
- Isolate animation and delay lifetimes in regression tests while preserving default indicators.

### Upgrade notes

- Existing direct `refresh()` and `refresh(showsIndicator:)` calls still compile. The full method is now `refresh(showsIndicator:scrollToTop:)`; wrap stored one-argument method references in a closure, for example `{ loading.refresh(showsIndicator: $0) }`.
- Default animation duration changes from 0.25 to 0.35 seconds. Fast responses wait for the reveal before closing; exhausted footers no longer reserve space.
- Native return APIs require forwarding `scrollViewDidEndScrollingAnimation`. The configured duration does not set native scroll duration; zero disables animation.
- Default indicators and initializer defaults remain available. iOS 16 and Swift 6 tooling in Swift 5 language mode remain unchanged.

### Validation

- 74 package tests, 8 Pager/Refresher integration tests, and all 5 existing example UI tests passed with Xcode 27.1 on iOS 27.0.
- No physical-device or iOS 16 runtime validation was performed for this release.

## 0.2.0 — 2026-09-21

### Changes

- Animate the transition from a released pull to the refresh height, instead of allowing UIKit's inset adjustment to snap there. Fast requests close from the current animation position.
- Add `refresh(showsIndicator: false)` for initial loading without a refresh header, extra top inset or closing animation. Request state, cancellation and pagination coordination remain unchanged.
- Document how scroll containers can use `.refreshing` and `.finishing` while preserving each owner's inset contribution.
- Cover silent refresh completion and failure, cancellation/reset/detach, late callbacks, subsequent visible refreshes, automatic pagination and external insets during closing.

### Upgrade notes

- Update a dependency constrained to the next minor version from `0.1.0` to start at `0.2.0`.
- Direct `refresh()` calls remain valid. The method is now `refresh(showsIndicator: Bool = true)`; wrap a stored no-argument method reference in a closure, such as `{ loading.refresh() }`.
- `animationDuration` now controls both the release transition and closing. Platform and tooling requirements remain iOS 16+ and Swift 6 tooling in Swift 5 language mode.

### Validation

- 41 Swift Testing tests (51 parameter-expanded executions) and 5 XCUITest tests passed with Xcode 27.0 on iOS 27.0 simulators.
- Four additional real-gesture probes covered fast and slow refreshes in both table and collection views.
- iOS 16 runtime and physical-device behavior were not verified.

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
