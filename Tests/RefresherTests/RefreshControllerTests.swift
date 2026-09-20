// Created by weixi on 2026/09/20.

import Combine
@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct RefreshControllerTests {
    @Test func duplicateRefreshIsIgnored() async {
        let fixture = ScrollFixture()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
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
            onRefresh: request.run,
            animate: animation.animate
        )
        controller.refresh()
        await request.started()
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(animation.completions.count == 1)
        controller.refresh()
        await request.started(2)
        let inset = fixture.scrollView.contentInset.top
        animation.completions[0]()
        #expect(controller.state.refresh == .refreshing)
        #expect(fixture.scrollView.contentInset.top == inset)
        #expect(!header.isHidden)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .finishing }
        animation.completions[1]()
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset.top == 0)
    }

    @Test func pullingCanCoexistWithPageLoadingThenSupersedeIt() async {
        let fixture = ScrollFixture()
        let page = ControlledOperation()
        let refresh = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
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
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: request.run
        )
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
        #expect(!fixture.scrollView.subviews.contains { $0 is any RefreshHeader })
        withExtendedLifetime((a, b)) {}
    }

    @Test func realClosingAnimationSettlesAndRestoresInsets() async {
        let fixture = ScrollFixture(mounted: true)
        fixture.scrollView.contentInset.top = 19
        fixture.scrollView.contentOffset.y = -19
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: .init(animationDuration: 0.03),
            onRefresh: {}
        )
        controller.refresh()
        await waitForState(controller) { $0.refresh == .idle }
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == -19)
    }

    @Test func cancellingWhileDraggingRequiresANewGesture() async {
        let fixture = ScrollFixture()
        var calls = 0
        let controller = RefreshController(scrollView: fixture.scrollView, onRefresh: { calls += 1 })
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
        var controller: RefreshController? = RefreshController(scrollView: fixture.scrollView, onRefresh: request.run)
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
