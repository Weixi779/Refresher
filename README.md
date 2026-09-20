# Refresher

UIKit pull-to-refresh and pagination, iOS 16+. A standalone Swift Package with no third-party dependencies. Built with Swift 6 tooling in Swift 5 language mode.

One controller owns loading. Your async closures own data. Headers and footers only render their state.

## Installation

Requires iOS 16+ and Swift 6 tooling (Xcode 16+). The package uses Swift 5 language mode.

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/Weixi779/Refresher.git`, and select **Up to Next Minor Version** starting at **0.1.0**. Link the `Refresher` product to your app target.

For a `Package.swift` dependency:

```swift
dependencies: [
    .package(
        url: "https://github.com/Weixi779/Refresher.git",
        .upToNextMinor(from: "0.1.0")
    ),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "Refresher", package: "Refresher")]
    ),
]
```

See the [v0.1.0 release notes](https://github.com/Weixi779/Refresher/releases/tag/v0.1.0) and [changelog](CHANGELOG.md). To work on the library locally, add a checkout of this repository as a local package instead.

## Use

Retain a controller alongside your scroll view:

```swift
import Refresher

loading = RefreshController(
    scrollView: collectionView,
    onRefresh: { [weak self] in
        guard let self else { return }
        let page = try await service.firstPage()
        try Task.checkCancellation()
        await apply(page.items)
        loading.loadMoreAvailability = page.hasMore ? .ready : .exhausted
    },
    onLoadMore: { [weak self] in
        guard let self else { return }
        let page = try await service.nextPage()
        try Task.checkCancellation()
        await append(page.items)
        loading.loadMoreAvailability = page.hasMore ? .ready : .exhausted
    }
)

loading.refresh()
```

The controller observes offset, content size, bounds, insets and the pan gesture. After mounting the scroll view, call `loading.contentDidChange()` (for example in `viewDidAppear`). Call it after an external list/layout transaction when UIKit has not emitted a geometry change. The Example also forwards `viewDidLayoutSubviews`.

Provide only `onRefresh` for refresh alone, or only `onLoadMore` for pagination alone. Pagination starts as `.unavailable`; use `.ready` when more data can be requested and `.exhausted` when finished. An initial `loadMoreAvailability: .ready` permits mounted short/empty content to start loading automatically.

## Behavior

| Input | Result |
| --- | --- |
| Pull past the header height and release | Starts refresh. A cancelled gesture does not. |
| `refresh()` | Starts even before mounting; reveals the header only if already at the top. |
| Refresh while a page loads | Cancels that page and starts refresh. |
| Duplicate request | Ignored. Refresh during its closing animation may start a new refresh. |
| `loadMore()` | Explicit page request when `.ready` and no operation is running. |
| Near the bottom | Automatic page request when mounted, active and `.ready`. |
| Successful pagination | Re-evaluates after publishing completion. Continues automatically only after content height grows. |
| Thrown error / cancellation error | Ends loading; automatic pagination waits for a new drag or explicit request. |
| `isActive = false` | Blocks new requests without cancelling accepted work. This is an admission switch, not a visibility binding. |
| `cancel()` | Cancels current work and waits for fresh user interaction. |
| `reset()` | Cancels old work and clears pagination gates for a replaced data set. Keeps the supplied availability. |
| `detach()` | Cancels work, removes indicators, invalidates observations and removes owned inset contributions synchronously. Terminal and idempotent. |

Operations run on `MainActor` and may suspend. Check cancellation before committing data, and await your own list updates before returning. Refresher ignores stale results for its own state; it cannot undo arbitrary writes made by a cancellation-ignoring closure. Handle error presentation in the closure and rethrow so automatic loading can stop. No retry footer or application error policy is imposed.

Automatic pagination is deliberately bounded by visible progress. A backend may return an empty page with another cursor: fetch through that condition inside your operation, or explicitly request another page. Content height is a guard against repeated automatic no-ops, not a claim that the server has no more data.

## Observe or customize

```swift
subscription = loading.states.sink { state in
    // Main-thread, synchronous delivery. Reentrant inputs are queued.
    // With a direct subscription, loading.state == state throughout this callback.
}

final class MyHeader: UIView, RefreshHeader {
    func render(_ state: RefreshState) {
        // idle, pulling(progress: 0...1), refreshing, finishing
    }
}

final class MyFooter: UIView, LoadMoreFooter {
    func render(_ state: LoadMoreState) {
        // unavailable, idle, loading, exhausted
    }
}
```

Pass custom views via `header:` / `footer:`. The controller mounts and sizes these views directly; the views do not start requests or own loading state. `Configuration` sets header/footer heights, preload distance and closing duration. Defaults use system colors, a spinner and a pull arrow; there are no Motion or theme dependencies.

Initial replay and later subscriber demand use the same event boundary as state transitions. On MainActor, replay stays synchronous and commands issued inside the callback run after replay returns. Requests made from other executors (including `AsyncPublisher.values`) are forwarded to MainActor. Returned Combine demand is accounted for before queued state changes are published.

`LoadingState` contains separate optional refresh and pagination states because pulling can coexist with an accepted page. A renderer sees the previous committed public snapshot while preparing the next presentation. Subscribers receive that next snapshot only after rendering finishes. As with any publisher, adding asynchronous scheduling operators changes when a subscriber observes the value.

## Ownership

Use one controller per scroll view; do not combine it with another refresh control or inset-owning refresh library. It does not replace `UIScrollView.delegate`.

The page normally owns the controller and its view tree. Explicitly call `detach()` before replacing/removing the component on a scroll view that remains alive. Releasing only the controller does **not** promise to remove UI from a surviving scroll view. Deinitialization cancels the request; no asynchronous deinit cleanup or `isolated deinit` is used.

Inset adjustments are additive. Other owners can adjust `contentInset` while loading; preserve existing contributions when doing so (for example `contentInset.top += delta`). `detach()` removes only Refresher's current contribution. UIKit owns adjusted safe-area insets. Layout transitions and keyboard inset changes should complete before `contentDidChange()`.

## Example and tests

Open `Example/RefresherExample.xcodeproj`, select `RefresherExample`, and run on an iPhone or iPad simulator. No generator, server, signing setup for the simulator, or asset download is needed. The screen supports list/grid, real pull gestures, automatic pagination, short content, injected failure, slow requests, cancellation, reset and detach/reattach.

```sh
# Supply a simulator UDID, or use a currently booted available simulator.
Scripts/test.sh unit [SIMULATOR_UDID]
Scripts/test.sh ui [SIMULATOR_UDID]
Scripts/test.sh all [SIMULATOR_UDID]
```

Unit tests use Swift Testing and controlled async completions. UI tests use XCUITest against the local Example. Results and logs go into ignored `Artifacts/` folders. Testing the iOS 16 deployment target with a newer simulator is not an iOS 16 runtime test.

See [research and design decisions](Docs/Research.md) and [verification record](Docs/Verification.md).

Licensed under Apache 2.0.
