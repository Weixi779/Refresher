// Created by weixi on 2026/09/20.

import Combine
@testable import Refresher
import Testing
import UIKit

@MainActor
final class ControlledOperation {
    enum Failure: Error { case requested }
    private(set) var calls = 0
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func run() async throws {
        calls += 1
        let call = calls
        try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
            startWaiters.removeValue(forKey: call)?.forEach { $0.resume() }
        }
    }

    func started(_ call: Int = 1) async {
        if calls >= call { return }
        await withCheckedContinuation { startWaiters[call, default: []].append($0) }
    }

    func finish(_ call: Int = 1, failing: Bool = false) {
        let continuation = continuations.removeValue(forKey: call)
        if failing { continuation?.resume(throwing: Failure.requested) }
        else { continuation?.resume() }
    }

    func finishAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

@MainActor
final class ScrollFixture {
    let scrollView = UIScrollView(frame: CGRect(
        x: 0,
        y: 0,
        width: 320,
        height: 600
    ))
    let window = UIWindow(frame: CGRect(
        x: 0,
        y: 0,
        width: 320,
        height: 600
    ))

    init(contentHeight: CGFloat = 2000, mounted: Bool = false) {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 320, height: contentHeight)
        if mounted { mount() }
    }

    func mount() {
        let owner = UIViewController()
        owner.view.addSubview(scrollView)
        window.rootViewController = owner
        window.isHidden = false
        window.layoutIfNeeded()
    }
}

@MainActor
final class RecordingHeader: UIView, RefreshHeader {
    var onRender: ((RefreshState) -> Void)?
    private(set) var states: [RefreshState] = []
    func render(_ state: RefreshState) {
        states.append(state)
        onRender?(state)
    }
}

@MainActor
final class AnimationDriver {
    var completions: [() -> Void] = []
    func animate(
        _: TimeInterval,
        changes: @escaping () -> Void,
        completion: @escaping () -> Void
    ) -> UIViewPropertyAnimator? {
        changes()
        completions.append(completion)
        return nil
    }
}

@MainActor
func waitForState(_ controller: RefreshController, _ predicate: @escaping (LoadingState) -> Bool) async {
    for await state in controller.states.values {
        if predicate(state) { return }
    }
}

@MainActor
func drainMainQueue() async {
    for _ in 0 ..< 4 {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

let immediate = RefreshController.Configuration(animationDuration: 0)
