// Created by weixi on 2026/10/13.

@testable import Refresher
import Testing
import UIKit

@MainActor
struct RefreshCompletionDelayTests {
    @Test(
        "Interrupting the completion pause releases it without restarting a return",
        arguments: ["gesture", "inactive", "cancel"]
    )
    func interruptPause(reason: String) async {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize.height = 4000
        var activity: [Bool] = []
        let pause = ControlledRefreshPause()
        let binding = ScrollBinding(
            scrollView: scroll,
            header: RecordingHeader(),
            footer: nil,
            configuration: .init(
                refreshHeight: 70,
                animationDuration: 0,
                refreshCompletionDelay: 1,
                onReturnActivityChanged: { activity.append($0) }
            ),
            sleep: pause.sleep
        )
        defer { binding.detach() }
        binding.beginRefresh(reveal: true, scrollToTop: true)
        var finished = false
        var cancelled = false
        let preparation = Task { @MainActor in
            do {
                try await binding.prepareForRefreshContentUpdate()
            } catch is CancellationError {
                cancelled = true
            } catch {
                Issue.record(error)
            }
            finished = true
        }
        await drainMainQueue()
        #expect(pause.duration == 1)
        #expect(!finished)
        let returns = activity.count
        switch reason {
        case "gesture": binding.interruptAnimation(gestureTakeover: true)
        case "inactive": binding.endReturn(interrupted: true)
        default:
            preparation.cancel()
            binding.cancelRefresh()
        }
        scroll.contentOffset.y = 100
        await drainMainQueue()
        #expect(finished, "The one-second pause should be released immediately on interruption")
        await preparation.value
        #expect(cancelled == (reason == "cancel"))
        #expect(activity.count == returns, "Interruption must not start the closing return")
        #expect(scroll.contentOffset.y == 100)
        #expect(scroll.contentInset.top == 0)
    }

    @Test(
        "Tab completion pauses after the response, even when loading was already visible",
        arguments: [false, true]
    )
    func pauseBeforeClosing(preparesContent: Bool) async throws {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize.height = 4000
        let pause = ControlledRefreshPause()
        let binding = ScrollBinding(
            scrollView: scroll,
            header: RecordingHeader(),
            footer: nil,
            configuration: .init(
                refreshHeight: 70,
                animationDuration: 0,
                refreshCompletionDelay: 0.2
            ),
            sleep: pause.sleep
        )
        defer { binding.detach() }
        scroll.contentOffset.y = 300
        binding.beginRefresh(reveal: true, scrollToTop: true)
        #expect(pause.duration == nil)
        var completed = false
        let preparation = Task { @MainActor in
            if preparesContent {
                try await binding.prepareForRefreshContentUpdate()
                binding.finishRefresh { completed = true }
            } else {
                binding.finishRefresh { completed = true }
            }
        }
        await drainMainQueue()
        #expect(pause.duration == 0.2)
        #expect(!completed)
        #expect(scroll.contentOffset.y == -70)
        #expect(scroll.contentInset.top == 70)
        pause.resume()
        try await preparation.value
        await drainMainQueue()
        #expect(completed, "Content preparation must consume the pause; finishing must not pause twice")
        #expect(scroll.contentInset.top == 0)
        #expect(scroll.contentOffset.y == 0)
    }
}
