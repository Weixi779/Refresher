// Created by weixi on 2026/09/20.

import Combine
@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct RefreshControllerTests {
    @Test("Interrupting a refresh settles its animation and preserves the supplied position")
    func interruptionPreservesOffset() throws {
        let fixture = ScrollFixture()
        let animations = ControlledRefreshAnimations()
        let scroll = fixture.scrollView
        scroll.contentInset.top = 120
        scroll.contentOffset.y = -120
        let binding = ScrollBinding(
            scrollView: scroll,
            header: RecordingHeader(),
            footer: nil,
            configuration: .init(refreshHeight: 70),
            animate: animations.animate
        )
        binding.refreshOriginProvider = { -120 }
        defer { binding.detach() }
        binding.beginRefresh(reveal: true)
        let opening = try #require(animations.sessions.first)
        scroll.contentOffset.y = -145
        binding.interruptAnimation(gestureTakeover: true)
        #expect(opening.result == false)
        #expect(scroll.contentOffset.y == -145)
        opening.finish(true)
        #expect(scroll.contentOffset.y == -145)
    }

    @Test("Refresh geometry clips below chrome at explicit opening and closing positions")
    func headerClippingAtPositions() throws {
        let fixture = ScrollFixture()
        let scroll = fixture.scrollView
        scroll.contentInset.top = 120
        scroll.contentOffset.y = -120
        let header = RecordingHeader()
        let binding = ScrollBinding(scrollView: scroll, header: header, footer: nil, configuration: .init(refreshHeight: 70))
        binding.refreshOriginProvider = { -120 }
        defer { binding.detach() }
        let viewport = try #require(header.superview)
        for offset: CGFloat in [-120, -125, -155, -190, -155, -125, -120, 300] {
            scroll.contentOffset.y = offset
            #expect(viewport.clipsToBounds)
            #expect(viewport.frame.minY - scroll.contentOffset.y == 120)
            #expect(viewport.bounds.height == max(0, -offset - 120))
            if offset < -120 { #expect(viewport.frame.maxY == 0) }
        }
    }

    @Test(arguments: [CGFloat(0), 10, 35, 70, 140])
    func pullClippingFollowsRestingOrigin(pull: CGFloat) throws {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset.top = 120
        fixture.scrollView.contentOffset.y = -120 - pull
        let header = RecordingHeader()
        let binding = ScrollBinding(
            scrollView: fixture.scrollView,
            header: header,
            footer: nil,
            configuration: .init(refreshHeight: 70)
        )
        defer { binding.detach() }
        let viewport = try #require(header.superview)
        #expect(viewport.clipsToBounds)
        #expect(viewport.frame.minY - fixture.scrollView.contentOffset.y == 120)
        #expect(viewport.frame.maxY == 0)
        #expect(header.convert(header.bounds, to: fixture.scrollView).minY == -70)
    }

    @Test(arguments: [false, true])
    func silentRefreshPreservesGeometryAndLaterRefreshShowsHeader(failing: Bool) async {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset.top = 19
        fixture.scrollView.contentOffset.y = -19
        let header = RecordingHeader()
        let request = ControlledOperation()
        let animation = AnimationDriver()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            footer: nil,
            onRefresh: request.run,
            animate: animation.animate
        )

        controller.refresh(showsIndicator: false)
        await request.started()
        #expect(controller.state.refresh == .refreshing)
        #expect(header.isHidden)
        #expect(header.states.allSatisfy { $0 == .idle })
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == -19)

        request.finish(failing: failing)
        await waitForState(controller) { $0.refresh == .idle }
        #expect(animation.completions.isEmpty)
        #expect(header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == -19)

        controller.refresh()
        await request.started(2)
        #expect(!header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 79)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(animation.completions.count == 2)
        animation.completions[1]()
        #expect(controller.state.refresh == .idle)
    }

    @Test func silentRefreshCompletesBeforeAutomaticPagination() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let header = RecordingHeader()
        let refresh = ControlledOperation()
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: header,
            footer: nil,
            onRefresh: refresh.run,
            onLoadMore: page.run
        )

        controller.refresh(showsIndicator: false)
        await refresh.started()
        controller.loadMoreAvailability = .ready
        controller.loadMore()
        await drainMainQueue()
        #expect(page.calls == 0)
        #expect(header.isHidden)

        refresh.finish()
        await page.started()
        #expect(controller.state.refresh == .idle)
        #expect(header.isHidden)
        controller.loadMoreAvailability = .exhausted
        page.finish()
        await waitForState(controller) { $0.loadMore == .exhausted }
    }

    @Test func duplicateRefreshIsIgnored() async {
        let fixture = ScrollFixture()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            onRefresh: request.run
        )
        controller.refresh()
        controller.refresh()
        await request.started()
        #expect(request.calls == 1)
        request.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test func refreshSupersedesPageAndLatePageCannotFinishRefresh() async {
        let fixture = ScrollFixture()
        let page = ControlledOperation()
        let refresh = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            loadMoreAvailability: .ready,
            onRefresh: refresh.run,
            onLoadMore: page.run
        )
        controller.loadMore()
        await page.started()
        controller.refresh()
        await refresh.started()
        page.finish()
        await drainMainQueue()
        #expect(controller.state.refresh == .refreshing)
        #expect(controller.state.loadMore == .idle)
        controller.loadMore()
        #expect(page.calls == 1)
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test(arguments: [false, true])
    func cancelledResultCannotFinishReplacement(failing: Bool) async {
        let fixture = ScrollFixture()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            onRefresh: request.run
        )
        controller.refresh()
        await request.started()
        controller.cancel()
        controller.refresh()
        await request.started(2)
        request.finish(1, failing: failing)
        await drainMainQueue()
        #expect(controller.state.refresh == .refreshing)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test func everySubscriberSeesSameFullSequenceAndGetter() {
        let fixture = ScrollFixture()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            onRefresh: {}
        )
        var first: [RefreshState?] = []
        var second: [RefreshState?] = []
        let a = controller.states.sink { state in
            #expect(controller.state == state)
            first.append(state.refresh)
            if state.refresh == .refreshing { controller.cancel() }
            #expect(controller.state == state)
        }
        let b = controller.states.sink { state in
            #expect(controller.state == state)
            second.append(state.refresh)
        }
        controller.refresh()
        #expect(first == [.idle, .refreshing, .idle])
        #expect(second == first)
        withExtendedLifetime((a, b)) {}
    }

    @Test func rendererReentryDoesNotExposeAnUnpublishedSnapshot() {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: header,
            footer: nil,
            onRefresh: {}
        )
        var seen: [RefreshState?] = []
        var nested: AnyCancellable?
        header.onRender = { state in
            if state == .refreshing {
                #expect(controller.state.refresh == .idle)
                nested = controller.states.sink { snapshot in
                    #expect(snapshot == controller.state)
                    seen.append(snapshot.refresh)
                }
                controller.cancel()
            }
        }
        controller.refresh()
        #expect(seen == [.idle, .refreshing, .idle])
        withExtendedLifetime(nested) {}
    }

    @Test func reentrantSettersAreNotDeduplicatedBeforeConsumption() {
        let fixture = ScrollFixture()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            loadMoreAvailability: .ready,
            onRefresh: {},
            onLoadMore: {}
        )
        var didSet = false
        let subscription = controller.states.sink { state in
            if state.refresh == .refreshing, !didSet {
                didSet = true
                controller.isActive = false
                controller.isActive = true
                controller.loadMoreAvailability = .unavailable
                controller.loadMoreAvailability = .ready
            }
        }
        controller.refresh()
        #expect(controller.isActive)
        #expect(controller.loadMoreAvailability == .ready)
        controller.cancel()
        withExtendedLifetime(subscription) {}
    }

    @Test func disableBlocksNewWorkWithoutCancellingAcceptedWork() async {
        let fixture = ScrollFixture()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            onRefresh: request.run
        )
        controller.isActive = false
        controller.refresh()
        #expect(controller.state.refresh == .idle)
        controller.isActive = true
        controller.refresh()
        await request.started()
        controller.isActive = false
        #expect(controller.state.refresh == .refreshing)
        request.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test func oldClosingAnimationCannotMutateNewRefresh() async {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let request = ControlledOperation()
        let animation = AnimationDriver()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            footer: nil,
            onRefresh: request.run,
            animate: animation.animate
        )
        controller.refresh()
        await request.started()
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(animation.completions.count == 2)
        #expect(animation.curves == [.easeInOut, .easeInOut])
        #expect(header.alpha == 0)
        #expect(!header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 0)
        controller.refresh()
        await request.started(2)
        #expect(header.alpha == 1)
        let inset = fixture.scrollView.contentInset.top
        animation.completions[1]()
        #expect(controller.state.refresh == .refreshing)
        #expect(fixture.scrollView.contentInset.top == inset)
        #expect(!header.isHidden)
        #expect(header.alpha == 1)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .finishing }
        animation.completions[3]()
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset.top == 0)
    }

    @Test func pullingAfterClosingRestoresHeaderVisibility() async {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let request = ControlledOperation()
        let animation = AnimationDriver()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            footer: nil,
            onRefresh: request.run,
            animate: animation.animate
        )
        controller.refresh()
        await request.started()
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(header.alpha == 0)
        animation.completions[1]()
        #expect(header.isHidden)

        fixture.scrollView.contentOffset.y = -30
        controller.scrollDidChange(.pan(.began))
        #expect(controller.state.refresh == .pulling(progress: 0.5))
        #expect(!header.isHidden)
        #expect(header.alpha == 1)
        controller.cancel()
    }

    @Test func pullingCanCoexistWithPageLoadingThenSupersedeIt() async {
        let fixture = ScrollFixture()
        let page = ControlledOperation()
        let refresh = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            loadMoreAvailability: .ready,
            onRefresh: refresh.run,
            onLoadMore: page.run
        )
        controller.loadMore()
        await page.started()
        fixture.scrollView.contentOffset.y = -70
        controller.scrollDidChange(.pan(.began))
        #expect(controller.state.refresh == .pulling(progress: 1))
        #expect(controller.state.loadMore == .loading)
        controller.scrollDidChange(.pan(.ended))
        await refresh.started()
        #expect(controller.state.refresh == .refreshing)
        #expect(controller.state.loadMore == .idle)
        page.finish()
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test(arguments: [UIGestureRecognizer.State.cancelled, .failed])
    func cancelledGestureDoesNotRefresh(phase: UIGestureRecognizer.State) async {
        let fixture = ScrollFixture()
        var calls = 0
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: nil,
            footer: nil,
            onRefresh: { calls += 1 }
        )
        fixture.scrollView.contentOffset.y = -100
        controller.scrollDidChange(.pan(.began))
        controller.scrollDidChange(.pan(phase))
        await drainMainQueue()
        #expect(calls == 0)
        #expect(controller.state.refresh == .idle)
    }

    @Test func detachDuringNotificationPreservesSequenceAndIgnoresLateResults() async {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let footer = DefaultLoadMoreFooter()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: header,
            footer: footer,
            loadMoreAvailability: .ready,
            onRefresh: request.run,
            onLoadMore: {}
        )
        #expect(header.superview?.superview === fixture.scrollView)
        #expect(footer.superview === fixture.scrollView)
        controller.refresh()
        await request.started()
        var sequence: [RefreshState?] = []
        let a = controller.states.sink { state in
            #expect(state == controller.state)
            if state.refresh == .finishing { controller.detach() }
        }
        let b = controller.states.sink { state in
            #expect(state == controller.state)
            sequence.append(state.refresh)
        }
        request.finish()
        await waitForState(controller) { $0.refresh == .idle }
        controller.refresh()
        controller.detach()
        #expect(sequence == [.refreshing, .finishing, .idle])
        #expect(fixture.scrollView.contentInset == .zero)
        #expect(header.superview == nil)
        #expect(footer.superview == nil)
        withExtendedLifetime((a, b)) {}
    }

    @Test func draggingInterruptsRealClosingAnimationAndRestoresHeader() async {
        let fixture = ScrollFixture(mounted: true)
        let header = RecordingHeader()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: .init(animationDuration: 0.1),
            header: header,
            footer: nil,
            onRefresh: request.run
        )
        controller.refresh()
        await request.started()
        // Finish the programmatic reveal before exercising the closing animation.
        try? await Task.sleep(for: .milliseconds(150))
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(header.alpha == 0)

        fixture.scrollView.contentOffset.y = -30
        controller.scrollDidChange(.pan(.began))
        await drainMainQueue()
        if case let .pulling(progress) = controller.state.refresh {
            #expect(progress > 0)
        } else {
            Issue.record("Dragging should resume pull feedback after interrupting the closing animation")
        }
        #expect(!header.isHidden)
        #expect(header.alpha == 1)
        #expect(fixture.scrollView.contentInset.top == 0)
        fixture.scrollView.contentOffset.y = -45
        #expect(header.superview?.bounds.height == 45)
        #expect(header.superview?.frame.minY == -45)
        #expect(header.superview?.frame.maxY == 0)
        controller.cancel()
    }

    @Test func realClosingAnimationSettlesAndRestoresInsets() async {
        let fixture = ScrollFixture(mounted: true)
        fixture.scrollView.contentInset.top = 19
        fixture.scrollView.contentOffset.y = -19
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: .init(animationDuration: 0.03),
            header: nil,
            footer: nil,
            onRefresh: {}
        )
        controller.refresh()
        await waitForState(controller) { $0.refresh == .idle }
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == -19)
    }

    @Test("Fast completion waits for either reveal or release before closing", arguments: [true, false])
    func fastCompletionWaitsForOpeningAnimationBeforeClosing(reveal: Bool) async throws {
        let fixture = ScrollFixture(mounted: true)
        fixture.scrollView.contentOffset.y = reveal ? 0 : -140
        let header = RecordingHeader()
        let animations = ControlledRefreshAnimations()
        let binding = ScrollBinding(
            scrollView: fixture.scrollView,
            header: header,
            footer: nil,
            configuration: .init(refreshHeight: 70),
            animate: animations.animate
        )
        defer { binding.detach() }
        binding.beginRefresh(reveal: reveal)
        var finished = false
        binding.finishRefresh { finished = true }
        await drainMainQueue()
        #expect(animations.sessions.count == 1)
        #expect(header.alpha == 1)
        #expect(fixture.scrollView.contentInset.top == 70)
        #expect(!finished)

        let release = try #require(animations.sessions.first)
        release.finish(true)
        await drainMainQueue()
        #expect(animations.sessions.count == 2)
        #expect(header.alpha == 0)
        #expect(fixture.scrollView.contentInset.top == 0)
        let closing = try #require(animations.sessions.last)
        closing.finish(true)
        #expect(finished)
    }

    @Test func completionPauseKeepsHeaderVisibleBeforeClosing() async {
        let fixture = ScrollFixture(mounted: true)
        let header = RecordingHeader()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: .init(animationDuration: 0, refreshCompletionDelay: 0.2),
            header: header,
            footer: nil,
            onRefresh: request.run
        )
        controller.refresh()
        await request.started()
        let completedAt = ContinuousClock.now
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(header.alpha == 1)
        #expect(!header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 60)
        await waitForState(controller) { $0.refresh == .idle }
        #expect(completedAt.duration(to: .now) >= .milliseconds(200))
        #expect(header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 0)
    }

    @Test func replacementRefreshCancelsPendingCompletionPause() async throws {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: .init(animationDuration: 0, refreshCompletionDelay: 0.03),
            header: header,
            footer: nil,
            onRefresh: request.run
        )
        controller.refresh()
        await request.started()
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        await drainMainQueue()
        controller.refresh()
        await request.started(2)
        // Wait beyond the cancelled pause so stale work has a chance to run.
        try await Task.sleep(for: .milliseconds(60))
        #expect(controller.state.refresh == .refreshing)
        #expect(header.alpha == 1)
        #expect(!header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 60)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test func cancellingWhileDraggingRequiresANewGesture() async {
        let fixture = ScrollFixture()
        var calls = 0
        let controller = RefreshController(scrollView: fixture.scrollView, header: nil, footer: nil, onRefresh: { calls += 1 })
        fixture.scrollView.contentOffset.y = -100
        controller.scrollDidChange(.pan(.began))
        controller.cancel()
        controller.scrollDidChange(.geometry)
        controller.scrollDidChange(.pan(.ended))
        await drainMainQueue()
        #expect(calls == 0)
        #expect(controller.state.refresh == .idle)
    }

    @Test func releasingControllerCancelsWithoutADeferredUICleanupTask() async {
        let fixture = ScrollFixture()
        let request = ControlledOperation()
        var controller: RefreshController? = RefreshController(scrollView: fixture.scrollView, header: nil, footer: nil, onRefresh: request.run)
        weak var weakController: RefreshController?
        weakController = controller
        controller?.refresh()
        await request.started()
        controller = nil
        #expect(weakController == nil)
        request.finish()
        await drainMainQueue()
        #expect(weakController == nil)
    }
}
