// Created by weixi on 2026/09/20.

import Combine
@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PaginationAndGeometryTests {
    @Test func shortContentFillsUntilExhausted() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        await page.started()
        fixture.scrollView.contentSize.height = 80
        page.finish()
        await page.started(2)
        controller.loadMoreAvailability = .exhausted
        page.finish(2)
        await waitForState(controller) { $0.loadMore == .exhausted }
        await drainMainQueue()
        #expect(page.calls == 2)
    }

    @Test func successfulNoOpDoesNotCreateAnAutomaticLoop() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        var calls = 0
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: { calls += 1 }
        )
        await drainMainQueue()
        #expect(calls == 1)
        controller.contentDidChange()
        await drainMainQueue()
        #expect(calls == 1)
        controller.loadMore()
        await drainMainQueue()
        #expect(calls == 2)
    }

    @Test func failureWaitsForFreshGestureEvenWhenContentGrows() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        await page.started()
        page.finish(failing: true)
        await waitForState(controller) { $0.loadMore == .idle }
        fixture.scrollView.contentSize.height = 80
        controller.contentDidChange()
        await drainMainQueue()
        #expect(page.calls == 1)
        controller.scrollDidChange(.pan(.began))
        await page.started(2)
        controller.loadMoreAvailability = .exhausted
        page.finish(2)
        await waitForState(controller) { $0.loadMore == .exhausted }
    }

    @Test func completionSubscriberCanDisableBeforeNextAutomaticPage() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        await page.started()
        let subscription = controller.states.sink { state in
            if state.loadMore == .idle { controller.isActive = false }
        }
        fixture.scrollView.contentSize.height = 80
        page.finish()
        await waitForState(controller) { $0.loadMore == .idle }
        await drainMainQueue()
        #expect(page.calls == 1)
        withExtendedLifetime(subscription) {}
    }

    @Test func refreshSettlementSubscriberCanDisablePagination() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let refresh = ControlledOperation()
        var pageCalls = 0
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: refresh.run,
            onLoadMore: { pageCalls += 1 }
        )
        controller.refresh()
        await refresh.started()
        controller.loadMoreAvailability = .ready
        let subscription = controller.states.sink { state in
            if state.refresh == .idle { controller.isActive = false }
        }
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
        await drainMainQueue()
        #expect(pageCalls == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test func mountSignalWorksWithoutAResize() async {
        let fixture = ScrollFixture(contentHeight: 40)
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        await drainMainQueue()
        #expect(page.calls == 0)
        let size = fixture.scrollView.bounds.size
        fixture.mount()
        #expect(fixture.scrollView.bounds.size == size)
        controller.contentDidChange()
        await page.started()
        controller.loadMoreAvailability = .exhausted
        page.finish()
        await waitForState(controller) { $0.loadMore == .exhausted }
    }

    @Test func zeroHeightDoesNotLoadUntilLaidOut() async {
        let fixture = ScrollFixture(contentHeight: 0, mounted: true)
        fixture.scrollView.bounds.size.height = 0
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        await drainMainQueue()
        #expect(page.calls == 0)
        fixture.scrollView.bounds.size.height = 600
        controller.contentDidChange()
        await page.started()
        controller.detach()
        page.finish()
    }

    @Test func resetStartsANewDataSessionAfterFailure() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        await page.started()
        page.finish(failing: true)
        await waitForState(controller) { $0.loadMore == .idle }
        controller.reset()
        await page.started(2)
        controller.loadMoreAvailability = .exhausted
        page.finish(2)
        await waitForState(controller) { $0.loadMore == .exhausted }
    }

    @Test func externalInsetsSurviveCancelAndDetach() {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset = UIEdgeInsets(
            top: 13,
            left: 4,
            bottom: 21,
            right: 7
        )
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            loadMoreAvailability: .ready,
            onRefresh: {},
            onLoadMore: {}
        )
        controller.refresh()
        #expect(fixture.scrollView.contentInset.top == 73)
        #expect(fixture.scrollView.contentInset.bottom == 69)
        fixture.scrollView.contentInset.top += 17
        fixture.scrollView.contentInset.bottom += 9
        controller.cancel()
        #expect(fixture.scrollView.contentInset.top == 30)
        controller.detach()
        #expect(fixture.scrollView.contentInset == UIEdgeInsets(
            top: 30,
            left: 4,
            bottom: 30,
            right: 7
        ))
    }

    @Test func finishingRefreshKeepsItsStateAndPreservesOtherInsetOwners() async {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset = UIEdgeInsets(top: 244, left: 4, bottom: 21, right: 7)
        fixture.scrollView.contentOffset.y = -244
        let header = RecordingHeader()
        let request = ControlledOperation()
        let animation = AnimationDriver()
        var pageCalls = 0
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            loadMoreAvailability: .ready,
            onRefresh: request.run,
            onLoadMore: { pageCalls += 1 },
            animate: animation.animate
        )
        controller.refresh()
        await request.started()
        #expect(fixture.scrollView.contentInset.top == 304)
        fixture.scrollView.contentInset.top += 17
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(!header.isHidden)
        #expect(header.states.last == .finishing)
        // The closing animation withdraws our contribution while the request
        // remains in finishing; a container must not assume a fixed extra height.
        #expect(fixture.scrollView.contentInset.top == 261)
        fixture.scrollView.contentInset.top -= 20
        fixture.scrollView.contentInset.bottom += 9
        controller.contentDidChange()
        controller.loadMore()
        await drainMainQueue()
        #expect(controller.state.refresh == .finishing)
        #expect(!header.isHidden)
        #expect(pageCalls == 0)

        #expect(animation.completions.count == 1)
        animation.completions[0]()
        #expect(controller.state.refresh == .idle)
        #expect(header.isHidden)
        #expect(fixture.scrollView.contentInset == UIEdgeInsets(top: 241, left: 4, bottom: 78, right: 7))
        controller.detach()
        #expect(fixture.scrollView.contentInset == UIEdgeInsets(top: 241, left: 4, bottom: 30, right: 7))
    }

    @Test func headerAndFooterTrackFractionalWidthAndContentSize() {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let footer = DefaultLoadMoreFooter()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: header,
            footer: footer,
            onRefresh: {},
            onLoadMore: {}
        )
        fixture.scrollView.bounds.size.width = 375.5
        fixture.scrollView.contentSize.height = 987.5
        controller.contentDidChange()
        #expect(header.frame.width == 375.5)
        #expect(footer.frame.width == 375.5)
        #expect(footer.frame.minY == 987.5)
        #expect(header.superview === fixture.scrollView)
        #expect(footer.superview === fixture.scrollView)
    }

    @Test func deepProgrammaticRefreshDoesNotJumpToTop() {
        let fixture = ScrollFixture()
        fixture.scrollView.contentOffset.y = 400
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: {}
        )
        controller.refresh()
        #expect(fixture.scrollView.contentOffset.y == 400)
        controller.cancel()
        #expect(fixture.scrollView.contentOffset.y == 400)
    }

    @Test func adjustedInsetIsExcludedFromPullDistance() {
        let fixture = ScrollFixture(mounted: true)
        fixture.scrollView.contentInsetAdjustmentBehavior = .always
        fixture.scrollView.contentInset.top = 23
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: {}
        )
        let resting = -fixture.scrollView.adjustedContentInset.top
        fixture.scrollView.contentOffset.y = resting - 30
        controller.scrollDidChange(.pan(.began))
        #expect(controller.state.refresh == .pulling(progress: 0.5))
        controller.scrollDidChange(.pan(.cancelled))
    }

    @Test func unavailableFooterOwnsNoInsetAndActivePageKeepsItsPresentation() async {
        let fixture = ScrollFixture()
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onLoadMore: page.run
        )
        #expect(fixture.scrollView.contentInset == .zero)
        #expect(!fixture.scrollView.alwaysBounceVertical)
        controller.loadMoreAvailability = .ready
        controller.loadMore()
        await page.started()
        controller.loadMoreAvailability = .unavailable
        #expect(controller.state.loadMore == .loading)
        #expect(fixture.scrollView.contentInset.bottom == 48)
        page.finish()
        await waitForState(controller) { $0.loadMore == .unavailable }
        #expect(fixture.scrollView.contentInset == .zero)
    }
}
