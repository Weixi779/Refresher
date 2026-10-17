//
//  StickyPagerRefreshTests.swift
//  RefresherTests
//
//  Created by weixi on 2026/10/10.
//

import Testing
import UIKit
#if canImport(Pager)
    @testable import Pager
#endif
@testable import Refresher

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StickyPagerRefreshTests {
    @Test(
        "An interruption before the response clears owned inset before replacing content",
        arguments: ["drag", "inactive", "earlyEnd"],
        [CGFloat(240), 0]
    )
    func interruptionBeforeResponse(action: String, replacementHeight: CGFloat) async throws {
        let fixture = ScrollFixture(contentHeight: 4000, mounted: true)
        let scroll = fixture.scrollView
        scroll.contentInset.top = 120
        scroll.contentOffset.y = 2400
        let operation = ControlledOperation()
        var activity: [Bool] = []
        var applied = false
        var refresh: RefreshController!
        refresh = RefreshController(
            scrollView: scroll,
            configuration: .init(
                refreshHeight: 70,
                animationDuration: 0.2,
                refreshCompletionDelay: 1,
                onReturnActivityChanged: { activity.append($0) }
            ),
            header: RecordingHeader(),
            footer: nil,
            onRefresh: {
                try await operation.run()
                try await refresh.prepareForRefreshContentUpdate()
                #expect(scroll.contentInset.top == 125, "Clean only the refresh inset before applying content")
                #expect(scroll.contentOffset.y == 100, "Do not restart the interrupted return")
                scroll.contentSize.height = replacementHeight
                applied = true
            }
        )
        let delegate = NativeRefreshDelegate(refresh)
        scroll.delegate = delegate
        defer { refresh.detach(); operation.finishAll() }
        refresh.refresh(scrollToTop: true)
        await operation.started()
        switch action {
        case "drag": refresh.scrollDidChange(.pan(.began))
        case "inactive": refresh.isActive = false
        default: refresh.scrollViewDidEndScrollingAnimation()
        }
        scroll.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        scroll.contentInset.top += 5 // Another owner's change must survive cleanup.
        #expect(scroll.contentInset.top == 195)
        #expect(!applied)
        let activityBeforeResponse = activity
        operation.finish()
        try await delegate.waitForIdle()
        #expect(applied)
        #expect(scroll.contentInset.top == 125)
        #expect(activity == activityBeforeResponse)
    }

    @Test(
        "Content waits for the resting return and cancellation never applies it",
        arguments: ["arrival", "lateArrival", "drag", "inactive", "cancel", "reset", "detach"]
    )
    func contentUpdateDuringReturn(action: String) async throws {
        let fixture = ScrollFixture(contentHeight: 4000, mounted: true)
        let scroll = fixture.scrollView
        scroll.contentInset.top = 120
        scroll.contentOffset.y = 2400
        let operation = ControlledOperation()
        var preparing = false
        var applied = false
        var refresh: RefreshController!
        refresh = RefreshController(
            scrollView: scroll,
            configuration: .init(refreshHeight: 70, animationDuration: 0.02),
            header: RecordingHeader(),
            footer: nil,
            onRefresh: {
                try await operation.run()
                preparing = true
                try await refresh.prepareForRefreshContentUpdate()
                applied = true
            }
        )
        let delegate = NativeRefreshDelegate(refresh)
        scroll.delegate = delegate
        defer { refresh.detach(); operation.finishAll() }
        refresh.refresh(scrollToTop: true)
        await operation.started()
        if action == "lateArrival" {
            scroll.contentOffset.y = -190
            refresh.scrollViewDidEndScrollingAnimation()
        }
        operation.finish()
        await drainMainQueue()
        #expect(preparing)
        if action != "lateArrival" { #expect(!applied) }
        switch action {
        case "arrival", "lateArrival":
            if action == "arrival" {
                scroll.contentOffset.y = -190
                refresh.scrollViewDidEndScrollingAnimation()
                await drainMainQueue()
            }
            scroll.setContentOffset(CGPoint(x: 0, y: -120), animated: false)
            refresh.scrollViewDidEndScrollingAnimation()
        case "drag": refresh.scrollDidChange(.pan(.began))
        case "inactive": refresh.isActive = false
        case "cancel": refresh.cancel()
        case "reset": refresh.reset()
        default: refresh.detach()
        }
        try await delegate.waitForIdle()
        #expect(applied == ["arrival", "lateArrival", "drag", "inactive"].contains(action))
        #expect(scroll.contentInset.top == 120)
        #expect(scroll.contentOffset.y == (["arrival", "lateArrival"].contains(action) ? -120 : 2400))
    }

    @Test("A pending request can return later without duplicating its request or inset", arguments: [false, true])
    func returnDuringRequest(silent: Bool) async throws {
        let fixture = ScrollFixture(contentHeight: 4000, mounted: true)
        let scroll = fixture.scrollView
        scroll.contentInset.top = 120
        scroll.contentOffset.y = 300
        let operation = ControlledOperation()
        let refresh = RefreshController(
            scrollView: scroll,
            configuration: .init(refreshHeight: 70, animationDuration: 0.02),
            header: RecordingHeader(),
            footer: nil,
            onRefresh: operation.run
        )
        let delegate = NativeRefreshDelegate(refresh)
        scroll.delegate = delegate
        defer { refresh.detach(); operation.finishAll() }
        refresh.refresh(showsIndicator: !silent)
        await operation.started()
        let expectedInset: CGFloat = silent ? 120 : 190
        refresh.refresh(scrollToTop: true)
        refresh.refresh(scrollToTop: true)
        #expect(operation.calls == 1)
        #expect(scroll.contentInset.top == expectedInset)
        operation.finish()
        await drainMainQueue()
        if !silent { #expect(refresh.state.refresh == .finishing) }
        // Drive both native phases in this hostless runner; App tests sample real frames.
        scroll.contentOffset.y = silent ? -120 : -190
        refresh.scrollViewDidEndScrollingAnimation()
        await drainMainQueue()
        scroll.setContentOffset(CGPoint(x: 0, y: -120), animated: false)
        refresh.scrollViewDidEndScrollingAnimation()
        try await delegate.waitForIdle()
        #expect(scroll.contentOffset.y == -120)
        #expect(scroll.contentInset.top == 120)
        #expect(operation.calls == 1)
    }

    @Test(
        "Leaving or cancelling clears the native return wait and ignores late callbacks",
        arguments: ["inactive", "cancel", "reset", "detach"]
    )
    func abandonReturn(action: String) async throws {
        let fixture = ScrollFixture(contentHeight: 4000, mounted: true)
        let scroll = fixture.scrollView
        scroll.contentInset.top = 120
        scroll.contentOffset.y = 300
        let operation = ControlledOperation()
        let refresh = RefreshController(
            scrollView: scroll,
            configuration: .init(refreshHeight: 70, animationDuration: 0.02),
            header: RecordingHeader(),
            footer: nil,
            onRefresh: operation.run
        )
        let delegate = NativeRefreshDelegate(refresh)
        scroll.delegate = delegate
        defer { refresh.detach(); operation.finishAll() }
        refresh.refresh(scrollToTop: true)
        await operation.started()
        operation.finish()
        await drainMainQueue()
        #expect(refresh.state.refresh == .finishing)
        switch action {
        case "inactive": refresh.isActive = false
        case "cancel": refresh.cancel()
        case "reset": refresh.reset()
        default: refresh.detach()
        }
        try await delegate.waitForIdle()
        refresh.scrollViewDidEndScrollingAnimation()
        #expect(scroll.contentOffset.y == 300)
        #expect(scroll.contentInset.top == 120)
        #expect(operation.calls == 1)
    }

    #if canImport(Pager)
        @Test("Dragging takes ownership of a return or closing animation", arguments: [false, true])
        func interruptReturn(closing: Bool) async throws {
            let fixture = ScrollFixture(contentHeight: 4000, mounted: true)
            let scroll = fixture.scrollView
            let overlay = try #require(scroll.superview)
            let coordinator = StickyScrollCoordinator(chrome: UIView(), overlay: overlay, headerHeight: 77, tabBarHeight: 43)
            coordinator.attach(scroll, id: "a")
            coordinator.activate("a")
            let operation = ControlledOperation()
            let header = RecordingHeader()
            let refresh = RefreshController(
                scrollView: scroll,
                configuration: .init(refreshHeight: 70, animationDuration: 0.2),
                header: header,
                footer: nil,
                onRefresh: operation.run
            )
            refresh.refreshOriginProvider = { coordinator.expandedTopOffset(of: "a") }
            let delegate = NativeRefreshDelegate(refresh)
            scroll.delegate = delegate
            defer { refresh.detach(); coordinator.detachAll(); operation.finishAll() }
            scroll.contentOffset.y = 300
            refresh.refresh(scrollToTop: true)
            await operation.started()
            if closing {
                await delegate.completeReturn(scroll)
                operation.finish()
                await drainMainQueue()
            }
            try await Task.sleep(for: .milliseconds(50))
            // A real pan first stops UIKit scrolling, which may send its end callback.
            scroll.setContentOffset(scroll.contentOffset, animated: false)
            refresh.scrollDidChange(.pan(.began))
            scroll.contentOffset.y = 100
            refresh.scrollDidChange(.pan(.changed))
            refresh.scrollDidChange(.pan(.ended))
            if !closing { operation.finish() }
            try await delegate.waitForIdle()
            try await Task.sleep(for: .milliseconds(300))
            #expect(scroll.contentOffset.y == 100)
            #expect(scroll.contentInset.top == 43)
            #expect(header.superview?.bounds.height == 0)

            refresh.refresh(scrollToTop: true)
            await operation.started(2)
            operation.finish(2)
            await drainMainQueue()
            await delegate.completeReturn(scroll)
            try await delegate.waitForIdle()
            #expect(scroll.contentOffset.y == -120)
            #expect(scroll.contentInset.top == 120)
        }

        @Test(
            "Fast requests finish the outward return before closing",
            arguments: [CGFloat(-120), -100, -43, 300, 2400]
        )
        func returnToRefresh(offset: CGFloat) async throws {
            let fixture = ScrollFixture(contentHeight: 4000, mounted: true)
            let scroll = fixture.scrollView
            let overlay = try #require(scroll.superview)
            let coordinator = StickyScrollCoordinator(chrome: UIView(), overlay: overlay, headerHeight: 77, tabBarHeight: 43)
            coordinator.attach(scroll, id: "a")
            coordinator.activate("a")
            let operation = ControlledOperation()
            let refresh = RefreshController(
                scrollView: scroll,
                configuration: .init(refreshHeight: 70, animationDuration: 0.1),
                header: RecordingHeader(),
                footer: nil,
                onRefresh: operation.run
            )
            refresh.refreshOriginProvider = { coordinator.expandedTopOffset(of: "a") }
            let delegate = NativeRefreshDelegate(refresh)
            scroll.delegate = delegate
            defer { refresh.detach(); coordinator.detachAll(); operation.finishAll() }
            scroll.contentOffset.y = offset
            delegate.offsets.removeAll()
            refresh.refresh(scrollToTop: true)
            if offset > -119 { #expect(scroll.contentOffset.y == offset) }
            await operation.started()
            operation.finish()
            await drainMainQueue()
            #expect(refresh.state.refresh == .finishing)
            await delegate.completeReturn(scroll)
            try await delegate.waitForIdle()
            #expect(scroll.contentOffset.y == -120)
            #expect(scroll.contentInset.top == 120)
            if offset > -119 {
                #expect(delegate.ended)
                #expect(delegate.insetAtEnd == 190)
            }
        }

        @Test("Pulling refresh starts only beyond the fully expanded top", arguments: [CGFloat(0), 2000])
        func pullAfterExpandedTop(contentHeight: CGFloat) async {
            let fixture = ScrollFixture(contentHeight: contentHeight)
            let scroll = fixture.scrollView
            let overlay = UIView(frame: scroll.bounds), chrome = UIView()
            overlay.addSubview(scroll)
            let header = RecordingHeader()
            let operation = ControlledOperation()
            let refresh = RefreshController(scrollView: scroll, configuration: immediate, header: header, footer: nil, onRefresh: operation.run)
            let coordinator = StickyScrollCoordinator(chrome: chrome, overlay: overlay, headerHeight: 77, tabBarHeight: 43)
            coordinator.attach(scroll, id: "a")
            coordinator.activate("a")
            defer {
                refresh.detach()
                coordinator.detachAll()
                operation.finishAll()
            }
            refresh.scrollDidChange(.pan(.began))
            // List reading, header unfolding, then the fully expanded origin.
            for offset: CGFloat in [200, 0, -43, -70, -100, -120] {
                scroll.contentOffset.y = offset
                refresh.scrollDidChange(.pan(.changed))
                #expect(refresh.state.refresh == .idle)
                #expect(operation.calls == 0)
            }
            scroll.contentOffset.y = -150
            refresh.scrollDidChange(.pan(.changed))
            #expect(refresh.state.refresh == .pulling(progress: 0.5))
            #expect(chrome.convert(chrome.bounds, to: overlay).minY == 0)
            #expect(header.convert(header.bounds, to: overlay).maxY == 150)
            refresh.scrollDidChange(.pan(.ended))
            #expect(refresh.state.refresh == .idle)
            #expect(operation.calls == 0)

            refresh.scrollDidChange(.pan(.began))
            scroll.contentOffset.y = -180
            refresh.scrollDidChange(.pan(.changed))
            #expect(refresh.state.refresh == .pulling(progress: 1))
            refresh.scrollDidChange(.pan(.ended))
            await operation.started()
            #expect(refresh.state.refresh == .refreshing)
            #expect(scroll.contentOffset.y == -180)
            #expect(chrome.convert(chrome.bounds, to: overlay).maxY == 120)
            #expect(header.convert(header.bounds, to: overlay).minY == 120)
            operation.finish()
            await waitForState(refresh) { $0.refresh == .idle }
            #expect(scroll.contentOffset.y == -120)
            #expect(scroll.contentInset.top == 120)
            #expect(coordinator.headerState.progress == 0)
        }

        @Test("Switching preserves real custom refresh through its finishing animation")
        func switchDuringRefresh() async {
            let a = ScrollFixture(), b = ScrollFixture()
            let overlay = UIView(frame: a.scrollView.bounds), chrome = UIView()
            overlay.addSubview(a.scrollView)
            overlay.addSubview(b.scrollView)
            let driver = AnimationDriver(), operation = ControlledOperation()
            let refresh = RefreshController(
                scrollView: a.scrollView, configuration: immediate,
                header: RecordingHeader(), footer: nil, onRefresh: operation.run,
                animate: driver.animate
            )
            let coordinator = StickyScrollCoordinator(chrome: chrome, overlay: overlay, headerHeight: 77, tabBarHeight: 43)
            coordinator.attach(a.scrollView, id: "a")
            coordinator.attach(b.scrollView, id: "b")
            coordinator.activate("a")
            defer {
                refresh.detach()
                coordinator.detachAll()
                operation.finishAll()
            }
            refresh.refresh()
            await operation.started()
            #expect(a.scrollView.contentOffset.y == -180)
            coordinator.activate("b")
            b.scrollView.contentOffset.y = 200
            coordinator.beginTransition(to: "a")
            coordinator.activate("a")
            #expect(a.scrollView.contentOffset.y == -180)
            #expect(coordinator.headerState.progress == 0)
            operation.finish()
            await waitForState(refresh) { $0.refresh == .finishing }
            // The injected driver applies closing geometry but holds completion.
            coordinator.activate("b")
            coordinator.beginTransition(to: "a")
            coordinator.activate("a")
            #expect(a.scrollView.contentOffset.y == -120)
            #expect(a.scrollView.contentInset.top == 120)
            driver.completions.forEach { $0() }
            await waitForState(refresh) { $0.refresh == .idle }
            #expect(coordinator.headerState.progress == 0)
        }
    #endif
}

@MainActor
private final class NativeRefreshDelegate: NSObject, UIScrollViewDelegate {
    let refresh: RefreshController
    var ended = false
    var offsets: [CGFloat] = []
    var insetAtEnd: CGFloat?

    init(_ refresh: RefreshController) {
        self.refresh = refresh
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        offsets.append(scrollView.contentOffset.y)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        ended = true
        insetAtEnd = scrollView.contentInset.top
        refresh.scrollViewDidEndScrollingAnimation()
    }

    func waitForIdle() async throws {
        for _ in 0 ..< 200 {
            if refresh.state.refresh == .idle { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Return did not settle: ended=\(ended), lastOffset=\(String(describing: offsets.last)), state=\(refresh.state)")
    }

    func completeReturn(_ scrollView: UIScrollView) async {
        // The package's hostless runner does not advance native scroll animations.
        // Real scrolling and intermediate positions are covered by HomePageLoadingTests.
        scrollView.delegate = nil
        scrollView.setContentOffset(CGPoint(x: 0, y: -190), animated: false)
        scrollView.delegate = self
        scrollViewDidEndScrollingAnimation(scrollView)
        await drainMainQueue()
        if refresh.state.refresh == .finishing {
            scrollView.delegate = nil
            scrollView.setContentOffset(CGPoint(x: 0, y: -120), animated: false)
            scrollView.delegate = self
            scrollViewDidEndScrollingAnimation(scrollView)
        }
    }
}
