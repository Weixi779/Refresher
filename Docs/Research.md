# Research and decisions

Reviewed 2026-09-20. These are references, not dependencies or requirements. Production source is independently implemented.

| Reference | Useful observation | What we deliberately leave behind |
| --- | --- | --- |
| [Apple UIRefreshControl](https://developer.apple.com/documentation/uikit/uirefreshcontrol) | A small UI-facing lifecycle: trigger, load, end. A good default when native refresh alone is sufficient. | Subclassing or hiding native internals to support arbitrary progress-driven headers and coordinated pagination. |
| [MJRefresh](https://github.com/CoderMJLee/MJRefresh/tree/5647d82cd7e0de8c59980c6cb2afff173978f481/MJRefresh/Base) | Normalize offset against adjusted inset; restore only the component's inset contribution; distinguish short content and repeat triggers. | Its inheritance tree, associated-object attachment API, historical collection-view workarounds and persistent refresh timestamps. |
| [SVPullToRefresh](https://github.com/samvermette/SVPullToRefresh/tree/a5f9dfee86a27c4e994d7edf93d0768c881d58bb/SVPullToRefresh) | Direct view ownership and understandable trigger/loading flow. | Legacy inset assumptions and effects nested inside state setters. |
| [ESPullToRefresh](https://github.com/eggswift/pull-to-refresh/tree/6bfa290dcb98e0bb5e43bd9bcf51cafca1640cef/Sources) | Replaceable presentation is useful. | Animator and component both owning state; overlapping progress/state/begin/end protocols; attachment deferred to the next run loop. |
| [DGElasticPullToRefresh](https://github.com/gontovnik/DGElasticPullToRefresh/tree/c525935d32f2989b3f0b24bd45b0fe1278aa2097/DGElasticPullToRefresh) | A specialized animation can live in a presentation view. | Elastic animation geometry, display links, observer registries and gesture suppression in a general loading engine. |

## Boundary

- UIKit, iOS 16+, one package, no external dependencies. Default system-colored indicators; custom headers and footers render one state each.
- One controller owns request admission, cancellation and public snapshots. A plain scroll binding owns observations, layout, inset contributions and the closing animation. No extra lifecycle UIView.
- All inputs enter a synchronous MainActor FIFO. A transition finishes before the next input runs. The public getter returns the last published snapshot, including while a renderer or subscriber reenters. Initial replay and delayed subscriber demand share this boundary.
- One operation identity remains valid through refresh's closing animation. Animation callbacks only send an event; they never subsequently hide a view or restore inset.
- Configuration setters are checked when consumed, not before queueing. Pagination evaluation is coalesced onto a later main-loop turn.
- Refresh supersedes pagination. Duplicate operations are ignored; pagination never supersedes refresh. Disabling admission does not cancel an accepted operation.
- The caller supplies async work and pagination availability. Work must check cancellation before applying results, and await its own list updates before returning. The component cannot undo arbitrary business writes.
- Failure requires a fresh drag or explicit request. Automatic pagination also requires content height to advance after the preceding page; this prevents a successful no-op from spinning indefinitely. Refresh resets that boundary. Empty/short content may load automatically once mounted.
- The owner retains the controller. Normal page teardown releases its view tree and observations. Removing/replacing the component on a surviving scroll view uses explicit, synchronous `detach()`. Releasing only the controller is not an implicit UI transaction.
- Mounting and external layout completion can call `contentDidChange()`. No hidden attachment sentinel, delayed deinit task or isolated deinit.

## Verification targets

Request and notification ordering; cancellation-resistant late completions; old animation completion after a new request; callback/getter consistency; reentrant setters; external inset changes; short content; failure/no-progress loops; detached and released ownership. The Example exercises real table and collection scrolling, gestures, cancellation, failure, mounting and rotation with XCUITest.

Deployment compatibility and runtime coverage are separate: build with an iOS 16 deployment target, and record the actual installed simulator runtime used in the test report.
