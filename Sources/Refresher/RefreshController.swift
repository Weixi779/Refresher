// Created by weixi on 2026/09/20.

import Combine
import UIKit

/// Retain alongside the scroll view. Call `detach()` to remove it from a surviving view.
@MainActor
public final class RefreshController {
    public typealias Operation = @MainActor () async throws -> Void

    public struct Configuration {
        public let refreshHeight: CGFloat
        public let loadMoreHeight: CGFloat
        public let preloadDistance: CGFloat
        public let animationDuration: TimeInterval

        public init(
            refreshHeight: CGFloat = 60,
            loadMoreHeight: CGFloat = 48,
            preloadDistance: CGFloat = 160,
            animationDuration: TimeInterval = 0.25
        ) {
            precondition(refreshHeight.isFinite && refreshHeight > 0)
            precondition(loadMoreHeight.isFinite && loadMoreHeight > 0)
            precondition(preloadDistance.isFinite && preloadDistance >= 0)
            precondition(animationDuration.isFinite && animationDuration >= 0)
            self.refreshHeight = refreshHeight
            self.loadMoreHeight = loadMoreHeight
            self.preloadDistance = preloadDistance
            self.animationDuration = animationDuration
        }
    }

    /// The last committed snapshot. Reentrant commands run after all current subscribers return.
    public var state: LoadingState {
        subject.value
    }

    public var states: AnyPublisher<LoadingState, Never> {
        StatePublisher(subject: subject, controller: self).eraseToAnyPublisher()
    }

    /// Gates new operations. Changing this does not cancel an accepted operation.
    public var isActive: Bool {
        get { active }
        set { send(.setActive(newValue)) }
    }

    public var loadMoreAvailability: LoadMoreAvailability {
        get { availability }
        set { send(.setAvailability(newValue)) }
    }

    private enum Kind { case refresh, loadMore }
    private enum Outcome { case success, failure, cancelled }
    private enum Event {
        case refresh(showsIndicator: Bool)
        case loadMore, cancel, reset, detach, contentChanged, evaluate
        case scroll(ScrollBinding.Change)
        case setActive(Bool)
        case setAvailability(LoadMoreAvailability)
        case completed(UInt64, Outcome)
        case settled(UInt64)
    }

    private struct RunningOperation {
        let id: UInt64
        let kind: Kind
        let task: Task<Void, Never>
    }

    private let onRefresh: Operation?
    private let onLoadMore: Operation?
    private let configuration: Configuration
    private let binding: ScrollBinding
    private let subject: CurrentValueSubject<LoadingState, Never>
    private var refreshState: RefreshState?
    private var availability: LoadMoreAvailability
    private var active = true
    private var attached = true
    private var dragging = false
    private var operation: RunningOperation?
    private var nextID: UInt64 = 0
    private var waitingForUser = false
    private var precedingPageHeight: CGFloat?
    private var events: [Event] = []
    private var draining = false
    private var evaluationScheduled = false

    public convenience init(
        scrollView: UIScrollView,
        configuration: Configuration = Configuration(),
        header: (any RefreshHeader)? = nil,
        footer: (any LoadMoreFooter)? = nil,
        loadMoreAvailability: LoadMoreAvailability = .unavailable,
        onRefresh: Operation? = nil,
        onLoadMore: Operation? = nil
    ) {
        self.init(
            scrollView: scrollView,
            configuration: configuration,
            header: header,
            footer: footer,
            loadMoreAvailability: loadMoreAvailability,
            onRefresh: onRefresh,
            onLoadMore: onLoadMore,
            animate: nil
        )
    }

    init(
        scrollView: UIScrollView,
        configuration: Configuration = Configuration(),
        header: (any RefreshHeader)? = nil,
        footer: (any LoadMoreFooter)? = nil,
        loadMoreAvailability: LoadMoreAvailability = .unavailable,
        onRefresh: Operation? = nil,
        onLoadMore: Operation? = nil,
        animate: ScrollBinding.Animate?
    ) {
        precondition(onRefresh != nil || onLoadMore != nil, "Provide at least one loading operation")
        self.configuration = configuration
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        availability = loadMoreAvailability
        refreshState = onRefresh == nil ? nil : .idle
        let initial = LoadingState(
            refresh: refreshState,
            loadMore: onLoadMore == nil ? nil : Self.restingPageState(loadMoreAvailability)
        )
        subject = CurrentValueSubject(initial)
        let header = onRefresh == nil ? nil : (header ?? DefaultRefreshHeader())
        let footer = onLoadMore == nil ? nil : (footer ?? DefaultLoadMoreFooter())
        if let animate {
            binding = ScrollBinding(
                scrollView: scrollView,
                header: header,
                footer: footer,
                configuration: configuration,
                animate: animate
            )
        } else {
            binding = ScrollBinding(
                scrollView: scrollView,
                header: header,
                footer: footer,
                configuration: configuration
            )
        }
        // Even initial rendering can call external code; use the same event boundary.
        draining = true
        binding.onChange = { [weak self] change in self?.scrollDidChange(change) }
        binding.render(initial)
        draining = false
        send(.contentChanged)
    }

    deinit {
        operation?.task.cancel()
    }

    /// Silent refreshes keep the same loading lifecycle without showing a header or adding a top inset.
    public func refresh(showsIndicator: Bool = true) {
        send(.refresh(showsIndicator: showsIndicator))
    }

    public func loadMore() {
        send(.loadMore)
    }

    public func cancel() {
        send(.cancel)
    }

    /// Cancel previous work and clear pagination gates when replacing the data set.
    public func reset() {
        send(.reset)
    }

    /// Terminal and idempotent. Cancels work, removes indicators, restores owned inset contributions.
    public func detach() {
        send(.detach)
    }

    /// Recheck after mounting or after an external list/layout transaction has completed.
    public func contentDidChange() {
        send(.contentChanged)
    }

    func scrollDidChange(_ change: ScrollBinding.Change) {
        send(.scroll(change))
    }

    private func send(_ event: Event) {
        events.append(event)
        withEventBoundary {}
    }

    private func withEventBoundary(_ action: () -> Void) {
        guard !draining else {
            action()
            return
        }
        draining = true
        action()
        var index = 0
        while index < events.count {
            let event = events[index]
            index += 1
            consume(event)
            publish()
        }
        events.removeAll(keepingCapacity: true)
        draining = false
    }

    private func consume(_ event: Event) {
        guard attached else { return }
        switch event {
        case let .refresh(showsIndicator):
            beginRefresh(reveal: true, showsIndicator: showsIndicator)
        case .loadMore:
            beginLoadMore(automatic: false)
        case .cancel:
            cancelOperation()
            waitingForUser = true
        case .reset:
            cancelOperation()
            waitingForUser = false
            precedingPageHeight = nil
            scheduleEvaluation()
        case .detach:
            cancelOperation()
            attached = false
            active = false
            binding.detach()
        case let .setActive(value):
            active = value
            if !value, case .pulling = refreshState { refreshState = .idle }
            scheduleEvaluation()
        case let .setAvailability(value):
            availability = value
            scheduleEvaluation()
        case .contentChanged:
            binding.layout()
            scheduleEvaluation()
        case let .scroll(change):
            handleScroll(change)
        case .evaluate:
            evaluationScheduled = false
            updatePull()
            beginLoadMore(automatic: true)
        case let .completed(id, outcome):
            completeOperation(id: id, outcome: outcome)
        case let .settled(id):
            guard operation?.id == id, operation?.kind == .refresh else { return }
            operation = nil
            refreshState = .idle
            binding.didFinishRefresh()
            scheduleEvaluation()
        }
    }

    private func handleScroll(_ change: ScrollBinding.Change) {
        switch change {
        case .geometry:
            binding.layout()
            scheduleEvaluation()
        case let .pan(phase):
            switch phase {
            case .began:
                dragging = true
                waitingForUser = false
                precedingPageHeight = nil
                updatePull()
            case .changed:
                updatePull()
            case .ended:
                updatePull()
                dragging = false
                if case let .pulling(progress) = refreshState, progress >= 1 {
                    beginRefresh(reveal: false)
                } else if case .pulling = refreshState {
                    refreshState = .idle
                }
            case .cancelled, .failed:
                dragging = false
                if case .pulling = refreshState { refreshState = .idle }
            default:
                break
            }
            scheduleEvaluation()
        }
    }

    private func updatePull() {
        guard onRefresh != nil, active, operation?.kind != .refresh else { return }
        if dragging {
            let progress = min(binding.geometry.pullDistance / configuration.refreshHeight, 1)
            refreshState = progress > 0 ? .pulling(progress: progress) : .idle
        }
    }

    private func beginRefresh(reveal: Bool, showsIndicator: Bool = true) {
        guard active, let onRefresh else { return }
        if operation?.kind == .refresh, refreshState != .finishing { return }
        cancelOperation()
        waitingForUser = false
        precedingPageHeight = nil
        refreshState = .refreshing
        binding.beginRefresh(reveal: reveal, showsIndicator: showsIndicator)
        start(.refresh, action: onRefresh)
    }

    private func beginLoadMore(automatic: Bool) {
        guard active, availability == .ready, operation == nil, let onLoadMore else { return }
        let geometry = binding.geometry
        if automatic {
            guard !waitingForUser, geometry.isMounted, geometry.viewportHeight > 0,
                  geometry.distanceToBottom <= configuration.preloadDistance else { return }
            if case .pulling = refreshState { return }
            if let precedingPageHeight, geometry.contentHeight <= precedingPageHeight { return }
        }
        waitingForUser = false
        precedingPageHeight = geometry.contentHeight
        start(.loadMore, action: onLoadMore)
    }

    private func start(_ kind: Kind, action: @escaping Operation) {
        nextID &+= 1
        let id = nextID
        let task = Task { @MainActor [weak self] in
            let outcome: Outcome
            do {
                try Task.checkCancellation()
                try await action()
                outcome = Task.isCancelled ? .cancelled : .success
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failure
            }
            self?.send(.completed(id, outcome))
        }
        operation = RunningOperation(
            id: id,
            kind: kind,
            task: task
        )
    }

    private func completeOperation(id: UInt64, outcome: Outcome) {
        guard let operation, operation.id == id else { return }
        if outcome != .success { waitingForUser = true }
        if operation.kind == .refresh {
            refreshState = .finishing
            binding.finishRefresh { [weak self] in self?.send(.settled(id)) }
        } else {
            self.operation = nil
            scheduleEvaluation()
        }
    }

    private func cancelOperation() {
        dragging = false
        operation?.task.cancel()
        operation = nil
        if onRefresh != nil { refreshState = .idle }
        binding.cancelRefresh()
    }

    private func scheduleEvaluation() {
        guard !evaluationScheduled else { return }
        evaluationScheduled = true
        DispatchQueue.main.async { [weak self] in self?.send(.evaluate) }
    }

    private func publish() {
        let next = LoadingState(refresh: refreshState, loadMore: pageState)
        guard next != subject.value else { return }
        if attached { binding.render(next) }
        subject.send(next)
    }

    private var pageState: LoadMoreState? {
        guard onLoadMore != nil else { return nil }
        return operation?.kind == .loadMore ? .loading : Self.restingPageState(availability)
    }

    private static func restingPageState(_ availability: LoadMoreAvailability) -> LoadMoreState {
        switch availability {
        case .unavailable: .unavailable
        case .ready: .idle
        case .exhausted: .exhausted
        }
    }

    /// CurrentValueSubject also publishes during demand, outside `send`.
    private struct StatePublisher: Publisher {
        typealias Output = LoadingState
        typealias Failure = Never

        let subject: CurrentValueSubject<LoadingState, Never>
        weak var controller: RefreshController?

        func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            subject.receive(subscriber: AnySubscriber(
                receiveSubscription: { [weak controller] subscription in
                    subscriber.receive(subscription: StateSubscription(upstream: subscription, controller: controller))
                },
                receiveValue: subscriber.receive,
                receiveCompletion: subscriber.receive
            ))
        }
    }

    /// The upstream is CurrentValueSubject's thread-safe subscription. Its reference is immutable;
    /// the weak controller is only read on MainActor. Cancellation remains safe from any thread.
    private final class StateSubscription: Subscription, @unchecked Sendable {
        private let upstream: any Subscription
        private weak var controller: RefreshController?

        init(upstream: any Subscription, controller: RefreshController?) {
            self.upstream = upstream
            self.controller = controller
        }

        func request(_ demand: Subscribers.Demand) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { requestOnMainActor(demand) }
            } else {
                // AsyncPublisher.values can request from a background executor.
                DispatchQueue.main.async { self.requestOnMainActor(demand) }
            }
        }

        func cancel() {
            upstream.cancel()
        }

        @MainActor
        private func requestOnMainActor(_ demand: Subscribers.Demand) {
            guard let controller else {
                upstream.request(demand)
                return
            }
            // Let upstream account for returned demand before draining callback commands.
            controller.withEventBoundary { upstream.request(demand) }
        }
    }
}
