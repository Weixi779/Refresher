# Verification

Verified 2026-09-21 with Xcode 27.0 (27A266a), Swift 6.4, iPhone 18 Pro simulators running iOS 27.0 (24A434). Package and Example deployment targets remain **iOS 16.0**.

| Check | Result |
| --- | --- |
| Package build and Swift Testing | 41 tests passed; 51 parameter-expanded executions; zero failures or skips |
| Example build and XCUITest | 5 tests passed; zero failures or skips |
| Real animation | Release settles at the refresh height; fast completion closes from the current animation position; closing restores the existing top inset |
| Visual inspection | Example running in dark mode; controls, state text and table layout inspected |
| Formatting and patch checks | SwiftFormat completed; `git diff --check` passed; test script syntax checked |

The UI suite performs real pulls on both table and collection views, scrolls through pagination to exhaustion, recovers from failure, cancels and replaces a slow request, detaches during refresh, reattaches, rotates and refreshes again, and fills short content automatically.

The core suite separately covers full multi-subscriber state sequences, getter/callback consistency, initial replay, delayed and finite subscriber demand, async values, cancellation during replay, publisher lifetime, renderer reentry, false→true setters within one notification, request replacement, cancellation-resistant late results, an old animation completing during a new refresh, mounting without resizing, zero viewport height, external/adjusted insets, fractional layout sizes, deep programmatic refresh, failure and no-progress loop prevention, ownership release and resetting a data session.

The v0.2.0 silent-refresh update adds seven test methods (13 parameter-expanded executions). They cover success and failure at the top and deep in the list, the unchanged public state sequence with a hidden header and no closing animation, duplicate admission, late pagination completions, cancel/reset/detach with external insets, an old closing animation during a silent replacement, subsequent visible refreshes, automatic pagination, and external inset changes while a visible refresh is finishing. The existing five UI tests also pass after this update. No Podcast-iOS or pager integration was executed by this package verification.

The release-animation fix adds two core tests: releasing a pull animates to the refresh height without completing the request, and a fast request interrupts that animation at its current position before closing. Four additional real-gesture probes in a temporary Example copy cover fast and slow requests on both table and collection views. Display-link samples previously showed an approximately 81-point jump in one frame on release; after the fix, the return progresses continuously over the configured duration (0.25 seconds by default). These are simulator observations, not physical-device performance measurements.

## Local evidence

Results live under the ignored `Artifacts/` directory and are not included in the repository or release archive. The final review reran both suites successfully:

- Core: `Artifacts/test-vUxVoV/unit.xcresult` and `unit.log` (41 tests passed).
- Example UI: `Artifacts/test-gIdbqh/ui.xcresult` and `ui.log` (5 tests passed).
- Release-animation probes: `Artifacts/pull-release.xcresult` and `.log` (baseline), `Artifacts/pull-release-animated.xcresult` and `.log` (fix), with four UI tests passing in each run. Per-frame traces are in `Artifacts/pull-release-traces/` and `Artifacts/pull-release-animated-traces/`. These temporary probes are not part of the committed UI suite.
- Additional review probe: `Artifacts/review-short-page-retry.xcresult` and `.log` (2 UI tests passed in a temporary copy). These checked pagination-only short content after a failure, with default and explicitly enabled vertical bouncing. They are not part of the committed UI suite.
- Earlier visual inspection: `Artifacts/Example.png`.

Reproduce with `Scripts/test.sh all SIMULATOR_UDID`. No verification depends on the Podcast-iOS project.

## Findings fixed during verification

- Releasing a pull changed the top inset synchronously, allowing UIKit to clamp the offset to the refresh height in one frame. The inset and offset now animate together. A fast completion stops that animation at its current position before starting the closing animation.

- P2: `CurrentValueSubject` replayed state during the subscriber's demand request outside the controller's event boundary. Reentrant commands changed the getter during that callback; finite demand could also miss intermediate states. A private subscription adapter now guards the whole upstream demand request, including returned-demand bookkeeping, with the existing controller boundary. Background demand is forwarded to MainActor. Three new test methods failed before the fix; the complete core and Example UI suites passed after it.

- Example debug builds initially included an unused simulator architecture while its package dependency built only the active architecture. The Example now uses the ordinary active-architecture Debug setting.
- The first Example launch exited because this SDK requires scene lifecycle adoption. The Example now starts its window through `UIWindowSceneDelegate`; the full UI suite passed after that correction.
- Frame writes now skip unchanged rectangles, preventing unnecessary layout feedback.
- Cancelling while dragging clears the current drag so releasing that gesture cannot restart refresh.
- Two test setups needed correction: a reentrant setter callback unintentionally repeated its own mutation on every subsequent snapshot, and an animation test expected top alignment while starting away from the resting top. The corrected tests assert the intended behavior without changing that behavior to satisfy the tests.

## Limits

The installed iOS 16.0 simulator runtime is unavailable on this macOS host. The sources compile with an iOS 16 deployment target, but actual runtime execution in this record is iOS 27.0, not iOS 16 or a physical device. This Xcode's UI testing frameworks report a newer minimum than the application target; that is a test-harness linker warning, not a raised Package/App deployment target.

No Motion integration, project migration, network backend, or application-specific list framework has been validated. In particular, a consumer must await its own diffable/batch-update completion and honor cancellation before writing data. The Example uses synchronous reload plus layout completion.
