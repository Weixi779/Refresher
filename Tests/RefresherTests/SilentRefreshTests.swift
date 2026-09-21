// Created by weixi on 2026/09/20.

import Combine
@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct SilentRefreshTests {
    @Test(arguments: [false, true], [CGFloat(-19), 400])
    func silentRefreshPreservesPresentationAndPublishesLifecycle(failing: Bool, offset: CGFloat) async {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset.top = 19
        fixture.scrollView.contentOffset.y = offset
        let header = RecordingHeader()
        let request = ControlledOperation()
        let animation = AnimationDriver()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            onRefresh: request.run,
            animate: animation.animate
        )
        var sequence: [RefreshState?] = []
        let subscription = controller.states.sink { state in
            #expect(controller.state == state)
            #expect(header.isHidden)
            sequence.append(state.refresh)
        }

        controller.refresh(showsIndicator: false)
        await request.started()
        controller.refresh()
        #expect(request.calls == 1)
        #expect(controller.state.refresh == .refreshing)
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == offset)

        request.finish(failing: failing)
        await waitForState(controller) { $0.refresh == .idle }
        #expect(sequence == [.idle, .refreshing, .finishing, .idle])
        #expect(header.states.allSatisfy { $0 == .idle })
        #expect(animation.completions.isEmpty)
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == offset)
        subscription.cancel()

        controller.refresh()
        await request.started(2)
        #expect(!header.isHidden)
        #expect(header.states.last == .refreshing)
        #expect(fixture.scrollView.contentInset.top == 79)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(animation.completions.count == 1)
        animation.completions[0]()
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset.top == 19)
    }

    @Test func silentRefreshSupersedesPaginationAndIgnoresItsLateCompletion() async {
        let fixture = ScrollFixture()
        let header = RecordingHeader()
        let page = ControlledOperation()
        let refresh = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            loadMoreAvailability: .ready,
            onRefresh: refresh.run,
            onLoadMore: page.run
        )
        controller.loadMore()
        await page.started()
        let inset = fixture.scrollView.contentInset
        controller.refresh(showsIndicator: false)
        await refresh.started()
        page.finish()
        await drainMainQueue()
        #expect(controller.state.refresh == .refreshing)
        #expect(controller.state.loadMore == .idle)
        #expect(fixture.scrollView.contentInset == inset)
        #expect(header.isHidden)
        refresh.finish()
        await waitForState(controller) { $0.refresh == .idle }
    }

    enum Interruption: CaseIterable {
        case cancel, reset, detach
    }

    @Test(arguments: Interruption.allCases)
    func interruptingSilentRefreshPreservesExternalInsets(interruption: Interruption) async {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset = UIEdgeInsets(top: 244, left: 4, bottom: 21, right: 7)
        fixture.scrollView.contentOffset.y = -244
        let header = RecordingHeader()
        let request = ControlledOperation()
        let animation = AnimationDriver()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
            onRefresh: request.run,
            animate: animation.animate
        )
        controller.refresh(showsIndicator: false)
        await request.started()
        fixture.scrollView.contentInset.top += 17
        fixture.scrollView.contentInset.bottom += 9
        fixture.scrollView.contentOffset.y = 400
        let inset = fixture.scrollView.contentInset

        switch interruption {
        case .cancel: controller.cancel()
        case .reset: controller.reset()
        case .detach: controller.detach()
        }
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset == inset)
        #expect(fixture.scrollView.contentOffset.y == 400)
        #expect(animation.completions.isEmpty)
        #expect(header.isHidden)

        controller.refresh()
        if interruption == .detach {
            request.finish()
            await drainMainQueue()
            #expect(request.calls == 1)
            #expect(header.superview == nil)
            #expect(controller.state.refresh == .idle)
        } else {
            await request.started(2)
            request.finish(1)
            await drainMainQueue()
            #expect(controller.state.refresh == .refreshing)
            #expect(!header.isHidden)
            #expect(fixture.scrollView.contentInset.top == inset.top + 60)
            controller.cancel()
            request.finish(2)
            await drainMainQueue()
        }
        #expect(fixture.scrollView.contentInset == inset)
        #expect(fixture.scrollView.contentOffset.y == 400)
    }

    @Test func oldClosingAnimationCannotSettleSilentReplacement() async {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset.top = 244
        fixture.scrollView.contentOffset.y = -244
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
        controller.refresh(showsIndicator: false)
        await request.started(2)
        fixture.scrollView.contentInset.top += 17
        fixture.scrollView.contentOffset.y = -261
        animation.completions[0]()
        #expect(controller.state.refresh == .refreshing)
        #expect(header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 261)

        request.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
        #expect(animation.completions.count == 1)
        #expect(fixture.scrollView.contentInset.top == 261)
        #expect(fixture.scrollView.contentOffset.y == -261)
        #expect(header.isHidden)
    }

    @Test(arguments: [false, true])
    func silentRefreshCoordinatesAutomaticPagination(failing: Bool) async {
        let fixture = ScrollFixture(contentHeight: 40, mounted: true)
        let header = RecordingHeader()
        let refresh = ControlledOperation()
        let page = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            header: header,
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

        refresh.finish(failing: failing)
        if failing {
            await waitForState(controller) { $0.refresh == .idle }
            await drainMainQueue()
            #expect(page.calls == 0)
            controller.scrollDidChange(.pan(.began))
        }
        await page.started()
        #expect(controller.state.refresh == .idle)
        #expect(header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 0)
        controller.loadMoreAvailability = .exhausted
        page.finish()
        await waitForState(controller) { $0.loadMore == .exhausted }
    }

    @Test func pullingAfterSilentRefreshShowsTheHeader() async {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset.top = 244
        fixture.scrollView.contentOffset.y = -244
        let header = RecordingHeader()
        let request = ControlledOperation()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            header: header,
            onRefresh: request.run
        )
        controller.refresh(showsIndicator: false)
        await request.started()
        request.finish()
        await waitForState(controller) { $0.refresh == .idle }
        fixture.scrollView.contentOffset.y = -314
        controller.scrollDidChange(.pan(.began))
        #expect(controller.state.refresh == .pulling(progress: 1))
        #expect(!header.isHidden)
        controller.scrollDidChange(.pan(.ended))
        await request.started(2)
        #expect(controller.state.refresh == .refreshing)
        #expect(!header.isHidden)
        #expect(fixture.scrollView.contentInset.top == 304)
        request.finish(2)
        await waitForState(controller) { $0.refresh == .idle }
        #expect(fixture.scrollView.contentInset.top == 244)
    }
}
