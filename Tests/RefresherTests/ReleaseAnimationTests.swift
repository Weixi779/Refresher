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

    @Test func quickCompletionClosesFromTheCurrentReleasePosition() async throws {
        let fixture = ScrollFixture(mounted: true)
        let request = ControlledOperation()
        var animations: [UIViewPropertyAnimator] = []
        var endPositions: [UIViewAnimatingPosition] = []
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: .init(animationDuration: 1),
            onRefresh: request.run,
            animate: { duration, changes, completion in
                let animation = UIViewPropertyAnimator(duration: duration, curve: .easeOut, animations: changes)
                animation.addCompletion { position in
                    endPositions.append(position)
                    completion()
                }
                animations.append(animation)
                animation.startAnimation()
                return animation
            }
        )
        fixture.scrollView.contentOffset.y = -140
        controller.scrollDidChange(.pan(.began))
        controller.scrollDidChange(.pan(.ended))
        await request.started()
        let release = try #require(animations.first)
        release.pauseAnimation()
        release.fractionComplete = 0.5

        request.finish()
        await waitForState(controller) { $0.refresh == .finishing }
        #expect(endPositions == [.current])
        #expect(release.state == .inactive)
        try #require(animations.count == 2)
        let closing = animations[1]
        closing.stopAnimation(false)
        closing.finishAnimation(at: .end)
        #expect(endPositions == [.current, .end])
        #expect(controller.state.refresh == .idle)
        #expect(fixture.scrollView.contentInset.top == 0)
        #expect(fixture.scrollView.contentOffset.y == 0)
    }
}
