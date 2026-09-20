// Created by weixi on 2026/09/20.

import Combine
@testable import Refresher
import Testing
import UIKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct StateSubscriptionTests {
    @Test(arguments: [false, true])
    func initialReplayDefersCommandsUntilCallbackReturns(refreshing: Bool) {
        let fixture = ScrollFixture()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: {}
        )
        if refreshing { controller.refresh() }
        var sequence: [RefreshState?] = []
        var depth = 0
        let subscription = controller.states.sink { state in
            depth += 1
            defer { depth -= 1 }
            #expect(depth == 1)
            #expect(controller.state == state)
            sequence.append(state.refresh)
            if sequence.count == 1 {
                controller.cancel()
                controller.refresh()
                #expect(controller.state == state)
            }
        }
        let expected: [RefreshState?] = refreshing ? [.refreshing, .idle, .refreshing] : [.idle, .refreshing]
        #expect(sequence == expected)
        controller.cancel()
        withExtendedLifetime(subscription) {}
    }

    @Test(arguments: [Subscribers.Demand.unlimited, .max(1)])
    func delayedDemandReplaysInsideTheSameBoundary(demand: Subscribers.Demand) {
        let fixture = ScrollFixture()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: {}
        )
        controller.refresh()
        var sequence: [RefreshState?] = []
        var reacted = false
        var depth = 0
        let subscriber = ManualStateSubscriber { state in
            depth += 1
            defer { depth -= 1 }
            #expect(depth == 1)
            #expect(controller.state == state)
            sequence.append(state.refresh)
            if !reacted {
                reacted = true
                controller.cancel()
                controller.refresh()
                #expect(controller.state == state)
            }
            return .max(1)
        }
        controller.states.subscribe(subscriber)
        #expect(sequence.isEmpty)
        subscriber.subscription?.request(demand)
        #expect(sequence == [.refreshing, .idle, .refreshing])
        subscriber.subscription?.cancel()
        controller.cancel()
    }

    @Test func cancellingDuringReplayPreventsQueuedUpdatesFromReachingSubscriber() {
        let fixture = ScrollFixture()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: {}
        )
        var sequence: [RefreshState?] = []
        let subscriber = ManualStateSubscriber { _ in .none }
        subscriber.onValue = { [weak subscriber] state in
            sequence.append(state.refresh)
            subscriber?.subscription?.cancel()
            controller.refresh()
            #expect(controller.state == state)
            return .unlimited
        }
        controller.states.subscribe(subscriber)
        subscriber.subscription?.request(.unlimited)
        #expect(sequence == [.idle])
        #expect(controller.state.refresh == .refreshing)
        controller.cancel()
    }

    @Test func asyncValuesReplayUsesTheSameBoundary() async {
        let fixture = ScrollFixture()
        let controller = RefreshController(
            scrollView: fixture.scrollView,
            configuration: immediate,
            onRefresh: {}
        )
        let values = controller.states.handleEvents(receiveOutput: { state in
            #expect(Thread.isMainThread)
            #expect(state.refresh == .idle)
            controller.refresh()
            #expect(controller.state == state)
        }).values
        for await state in values {
            #expect(state.refresh == .idle)
            break
        }
        #expect(controller.state.refresh == .refreshing)
        controller.cancel()
    }

    @Test func savedPublisherDoesNotRetainController() throws {
        let fixture = ScrollFixture()
        var controller: RefreshController? = RefreshController(scrollView: fixture.scrollView, onRefresh: {})
        weak var weakController: RefreshController?
        weakController = controller
        let publisher = try #require(controller?.states)
        controller = nil
        #expect(weakController == nil)
        var sequence: [RefreshState?] = []
        let subscription = publisher.sink { sequence.append($0.refresh) }
        #expect(sequence == [.idle])
        withExtendedLifetime(subscription) {}
    }
}

private final class ManualStateSubscriber: Subscriber {
    typealias Input = LoadingState
    typealias Failure = Never
    var subscription: (any Subscription)?
    var onValue: (LoadingState) -> Subscribers.Demand

    init(onValue: @escaping (LoadingState) -> Subscribers.Demand) {
        self.onValue = onValue
    }

    func receive(subscription: any Subscription) {
        self.subscription = subscription
    }

    func receive(_ input: LoadingState) -> Subscribers.Demand {
        onValue(input)
    }

    func receive(completion _: Subscribers.Completion<Never>) {}
}
