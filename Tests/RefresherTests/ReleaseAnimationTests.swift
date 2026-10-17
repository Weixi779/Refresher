// Created by weixi on 2026/09/21.

@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ReleaseAnimationTests {
    @Test func releaseAnimatesToRefreshHeightWithoutCompletingTheRequest() async throws {
        let fixture = ScrollFixture()
        fixture.scrollView.contentInset.top = 19
        let request = ControlledOperation()
        let animation = AnimationDriver()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            onRefresh: request.run,
            animate: animation.animate
        )
        fixture.scrollView.contentOffset.y = -159
        controller.scrollDidChange(.pan(.began))
        controller.scrollDidChange(.pan(.ended))
        await request.started()

        #expect(controller.state.refresh == .refreshing)
        #expect(fixture.scrollView.contentInset.top == 79)
        #expect(fixture.scrollView.contentOffset.y == -79)
        try #require(animation.completions.count == 1)
        animation.completions[0]()
        #expect(controller.state.refresh == .refreshing)
        #expect(fixture.scrollView.contentInset.top == 79)

        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        try #require(animation.completions.count == 2)
        animation.completions[1]()
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset.top == 19)
        #expect(fixture.scrollView.contentOffset.y == -19)
    }

    @Test func quickCompletionWaitsForReleaseBeforeClosing() async throws {
        let fixture = ScrollFixture()
        let request = ControlledOperation()
        let animations = ControlledRefreshAnimations()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            onRefresh: request.run,
            animate: animations.animate
        )
        defer { controller.detach(); request.finishAll() }
        fixture.scrollView.contentOffset.y = -140
        controller.scrollDidChange(.pan(.began))
        controller.scrollDidChange(.pan(.ended))
        await request.started()
        let release = try #require(animations.sessions.first)
        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(release.isActive)
        #expect(animations.sessions.count == 1)
        release.finish(true)
        await drainMainQueue()
        try #require(animations.sessions.count == 2)
        animations.sessions[1].finish(true)
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset.top == 0)
        #expect(fixture.scrollView.contentOffset.y == 0)
    }
}
