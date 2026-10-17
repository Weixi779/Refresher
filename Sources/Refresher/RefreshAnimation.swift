//
//  RefreshAnimation.swift
//  Refresher
//
//  Created by weixi on 2026/10/14.
//  Copyright © 2026 小宇宙. All rights reserved.
//

import UIKit

/// One animation lifetime. Cancellation settles waiters with `false`.
@MainActor
protocol RefreshAnimation: AnyObject {
    var isActive: Bool { get }
    func whenFinished(_ completion: @escaping (Bool) -> Void)
    func cancel()
}

/// Remembers the outcome even when a waiter subscribes after completion.
@MainActor
final class NativeRefreshAnimation: RefreshAnimation {
    private let animator: UIViewPropertyAnimator
    private var result: Bool?
    private var waiters: [(Bool) -> Void] = []
    var isActive: Bool {
        result == nil
    }

    init(
        duration: TimeInterval,
        curve: UIView.AnimationCurve,
        changes: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        animator = UIViewPropertyAnimator(duration: duration, curve: curve, animations: changes)
        animator.addCompletion { [weak self] position in
            self?.settle(position == .end)
            completion()
        }
        animator.startAnimation()
    }

    func whenFinished(_ completion: @escaping (Bool) -> Void) {
        if let result { completion(result) } else { waiters.append(completion) }
    }

    func cancel() {
        guard isActive else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
    }

    private func settle(_ finished: Bool) {
        guard result == nil else { return }
        result = finished
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0(finished) }
    }
}
