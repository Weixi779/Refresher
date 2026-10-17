//
//  ForceRefreshTests.swift
//  RefresherTests
//
//  Created by weixi on 2026/10/8.
//  Copyright © 2026 小宇宙. All rights reserved.
//

import Combine
@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ForceRefreshTests {
    @Test func inactiveRequestsCoalesceAndRefreshBeforePagination() async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let refresh = ControlledOperation()
        let page = ControlledOperation()
        defer { refresh.finishAll(); page.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, loadMoreAvailability: .ready,
            onRefresh: refresh.run, onLoadMore: page.run
        )
        controller.isActive = false
        controller.forceRefresh()
        controller.forceRefresh(showsIndicator: false)
        controller.contentDidChange()
        await drainMainQueue()
        #expect(refresh.calls == 0)
        #expect(page.calls == 0)
        controller.isActive = true
        await refresh.started()
        controller.isActive = false
        controller.isActive = true
        controller.contentDidChange()
        await drainMainQueue()
        #expect(refresh.calls == 1)
        #expect(page.calls == 0)
        refresh.finish()
        await page.started()
        controller.loadMoreAvailability = .exhausted
        page.finish()
        await waitForState(controller) { $0.loadMore == .exhausted }
        controller.isActive = false
        controller.isActive = true
        await drainMainQueue()
        #expect(refresh.calls == 1)
    }

    @Test(arguments: [false, true])
    func replacesRunningRefreshAndIgnoresLateCompletion(failing: Bool) async {
        let fixture = ScrollFixture()
        let refresh = ControlledOperation()
        defer { refresh.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, onRefresh: refresh.run
        )
        controller.refresh()
        await refresh.started()
        controller.forceRefresh()
        await refresh.started(2)
        refresh.finish(1, failing: failing)
        await drainMainQueue()
        #expect(controller.state.refresh == .refreshing)
        refresh.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
        controller.isActive = false
        controller.isActive = true
        await drainMainQueue()
        #expect(refresh.calls == 2)
    }

    @Test func inactiveInvalidationSurvivesOlderSuccessfulRefresh() async {
        let fixture = ScrollFixture()
        let refresh = ControlledOperation()
        defer { refresh.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, onRefresh: refresh.run
        )
        controller.forceRefresh()
        await refresh.started()
        controller.isActive = false
        controller.forceRefresh()
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
        controller.isActive = true
        await refresh.started(2)
        refresh.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test(arguments: [false, true])
    func failureWaitsForReactivationOrManualRefresh(manual: Bool) async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let refresh = ControlledOperation()
        let page = ControlledOperation()
        defer { refresh.finishAll(); page.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, loadMoreAvailability: .ready,
            onRefresh: refresh.run, onLoadMore: page.run
        )
        controller.forceRefresh()
        await refresh.started()
        refresh.finish(failing: true)
        await waitForState(controller) { $0.refresh == .idle }
        controller.contentDidChange()
        controller.isActive = true
        controller.scrollDidChange(.pan(.began))
        controller.scrollDidChange(.pan(.cancelled))
        controller.loadMore()
        await drainMainQueue()
        #expect(refresh.calls == 1)
        #expect(page.calls == 0)
        if manual {
            controller.refresh()
        } else {
            controller.isActive = false
            controller.isActive = true
        }
        await refresh.started(2)
        refresh.finish(2)
        await page.started()
        controller.loadMoreAvailability = .exhausted
        page.finish()
        await waitForState(controller) { $0.loadMore == .exhausted }
    }

    @Test(arguments: [false, true])
    func cancelRetainsPendingRequestWhileResetClearsIt(reset: Bool) async {
        let fixture = ScrollFixture()
        let refresh = ControlledOperation()
        defer { refresh.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, onRefresh: refresh.run
        )
        controller.forceRefresh()
        await refresh.started()
        if reset { controller.reset() } else { controller.cancel() }
        refresh.finish()
        await drainMainQueue()
        #expect(refresh.calls == 1)
        controller.isActive = false
        controller.isActive = true
        await drainMainQueue()
        if reset {
            #expect(refresh.calls == 1)
        } else {
            await refresh.started(2)
            refresh.finish(2)
            await waitForState(controller) { $0.refresh == .idle }
        }
    }

    @Test func forcedRefreshReplacesPagination() async {
        let fixture = ScrollFixture()
        let refresh = ControlledOperation()
        let page = ControlledOperation()
        defer { refresh.finishAll(); page.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, loadMoreAvailability: .ready,
            onRefresh: refresh.run, onLoadMore: page.run
        )
        controller.loadMore()
        await page.started()
        controller.forceRefresh()
        await refresh.started()
        page.finish()
        await drainMainQueue()
        #expect(controller.state.refresh == .refreshing)
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test(arguments: [false, true])
    func deferredRefreshUsesLatestIndicatorPreference(showsIndicator: Bool) async {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let refresh = ControlledOperation()
        defer { refresh.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: header, footer: nil, onRefresh: refresh.run
        )
        controller.isActive = false
        controller.forceRefresh(showsIndicator: !showsIndicator)
        controller.forceRefresh(showsIndicator: showsIndicator)
        controller.isActive = true
        await refresh.started()
        #expect(header.isHidden == !showsIndicator)
        #expect(fixture.scrollView.contentInset.top == (showsIndicator ? 60 : 0))
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    @Test func forceRefreshDuringCompletionNotificationSurvivesOldSettlement() async {
        let fixture = ScrollFixture()
        let refresh = ControlledOperation()
        defer { refresh.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, onRefresh: refresh.run
        )
        var replaced = false
        let subscription = controller.states.sink { state in
            if state.refresh == .finishing, !replaced {
                replaced = true
                controller.forceRefresh()
            }
        }
        controller.forceRefresh()
        await refresh.started()
        refresh.finish()
        await refresh.started(2)
        #expect(controller.state.refresh == .refreshing)
        refresh.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
        controller.isActive = false
        controller.isActive = true
        await drainMainQueue()
        #expect(refresh.calls == 2)
        withExtendedLifetime(subscription) {}
    }

    @Test func paginationOnlyControllerIgnoresForcedRefresh() async {
        let fixture = ScrollFixture()
        let page = ControlledOperation()
        defer { page.finishAll() }
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, loadMoreAvailability: .ready,
            onLoadMore: page.run
        )
        controller.forceRefresh()
        controller.loadMore()
        await page.started()
        page.finish()
        await waitForState(controller) { $0.loadMore == .idle }
        #expect(controller.state.refresh == nil)
    }

    @Test func detachDiscardsDeferredRefresh() async {
        let fixture = ScrollFixture()
        var calls = 0
        let controller = RefreshController(
            scrollView: fixture.scrollView, configuration: immediate,
            header: nil, footer: nil, onRefresh: { calls += 1 }
        )
        controller.isActive = false
        controller.forceRefresh()
        controller.detach()
        controller.isActive = true
        controller.forceRefresh()
        await drainMainQueue()
        #expect(calls == 0)
    }
}
