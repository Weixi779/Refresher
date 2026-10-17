//
//  ControlledRefreshTests.swift
//  RefresherTests
//
//  Created by weixi on 2026/10/14.
//  Copyright © 2026 小宇宙. All rights reserved.
//

@testable import Refresher
import Testing
import UIKit

@MainActor
final class ControlledRefreshAnimations {
    final class Session: RefreshAnimation {
        var result: Bool?
        var callbacks: [(Bool) -> Void] = []
        var isActive: Bool {
            result == nil
        }

        func whenFinished(_ completion: @escaping (Bool) -> Void) {
            if let result { completion(result) } else { callbacks.append(completion) }
        }

        func finish(_ success: Bool) {
            guard result == nil else { return }
            result = success
            let pending = callbacks
            callbacks.removeAll()
            pending.forEach { $0(success) }
        }

        func cancel() {
            finish(false)
        }
    }

    var sessions: [Session] = []
    func animate(
        _: TimeInterval,
        _: UIView.AnimationCurve,
        changes: @escaping () -> Void,
        completion: @escaping () -> Void
    ) -> (any RefreshAnimation)? {
        changes()
        let session = Session()
        session.whenFinished { _ in completion() }
        sessions.append(session)
        return session
    }
}

@MainActor
struct ControlledRefreshTests {
    @Test("The native adapter remembers cancellation for late observers")
    func nativeCancellation() {
        let view = UIView()
        var completions = 0
        let animation = NativeRefreshAnimation(duration: 1, curve: .linear, changes: { view.alpha = 0 }, completion: {
            completions += 1
        })
        var results: [Bool] = []
        animation.whenFinished { results.append($0) }
        animation.cancel()
        animation.whenFinished { results.append($0) }
        animation.cancel()
        #expect(results == [false, false])
        #expect(completions == 1)
    }

    @Test("Native scrolling waits for arrival and ignores callbacks after cancellation")
    func controlledReturn() {
        let fixture = ScrollFixture(mounted: true)
        let scroll = fixture.scrollView
        var targets: [CGPoint] = []
        let controller = ScrollToTopController(scrollView: scroll, scroll: { _, target, _ in targets.append(target) })
        var arrivals: [Bool] = []
        controller.scroll(to: CGPoint(x: 0, y: -70), animated: true) { arrivals.append($0) }
        #expect(targets == [CGPoint(x: 0, y: -70)])
        #expect(arrivals.isEmpty)
        scroll.contentOffset.y = -35
        controller.cancel()
        controller.scrollViewDidEndScrollingAnimation()
        #expect(arrivals == [false])
        controller.scroll(to: CGPoint(x: 0, y: -70), animated: true) { arrivals.append($0) }
        scroll.contentOffset.y = -70
        controller.scrollViewDidEndScrollingAnimation()
        #expect(arrivals == [false, true])
        #expect(!controller.isScrolling)
    }

    @Test("Closing waits for the reveal and the independently controlled pause")
    func controlledPause() async throws {
        let fixture = ScrollFixture()
        let animations = ControlledRefreshAnimations()
        let pause = ControlledRefreshPause()
        let binding = ScrollBinding(
            scrollView: fixture.scrollView,
            header: RecordingHeader(),
            footer: nil,
            configuration: .init(refreshCompletionDelay: 0.2),
            animate: animations.animate,
            sleep: pause.sleep
        )
        defer { binding.detach() }
        binding.beginRefresh(reveal: true)
        var finished = false
        binding.finishRefresh { finished = true }
        await drainMainQueue()
        #expect(pause.duration == nil)
        try #require(animations.sessions.first).finish(true)
        await drainMainQueue()
        #expect(pause.duration == 0.2)
        #expect(animations.sessions.count == 1)
        pause.resume()
        await drainMainQueue()
        #expect(animations.sessions.count == 2)
        #expect(!finished)
        try #require(animations.sessions.last).finish(true)
        #expect(finished)
    }

    @Test("Gesture takeover cancels the pause without leaving completion suspended")
    func cancelPause() async throws {
        let fixture = ScrollFixture()
        let animations = ControlledRefreshAnimations()
        let pause = ControlledRefreshPause()
        let binding = ScrollBinding(
            scrollView: fixture.scrollView,
            header: RecordingHeader(),
            footer: nil,
            configuration: .init(refreshCompletionDelay: 0.2),
            animate: animations.animate,
            sleep: pause.sleep
        )
        defer { binding.detach() }
        binding.beginRefresh(reveal: true)
        try #require(animations.sessions.first).finish(true)
        var finished = false
        binding.finishRefresh { finished = true }
        await drainMainQueue()
        #expect(pause.duration == 0.2)
        binding.interruptAnimation(gestureTakeover: true)
        await drainMainQueue()
        #expect(pause.cancelled)
        #expect(finished)
    }
}

@MainActor
final class ControlledRefreshPause {
    var duration: TimeInterval?
    var cancelled = false
    var continuation: CheckedContinuation<Void, Error>?
    func sleep(_ duration: TimeInterval) async throws {
        self.duration = duration
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in
                self.cancelled = true
                let continuation = self.continuation
                self.continuation = nil
                continuation?.resume(throwing: CancellationError())
            }
        }
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
