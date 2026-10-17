// Created by weixi on 2026/10/13.

import UIKit

/// Owns one native return animation. Forward `scrollViewDidEndScrollingAnimation`.
/// Reports activity so the host can opt into layout cooperation.
@MainActor
final class ScrollToTopController {
    typealias Scroll = @MainActor (UIScrollView, CGPoint, Bool) -> Void
    private let performScroll: Scroll

    private(set) var isScrolling = false
    private let onActivityChanged: ((Bool) -> Void)?
    private weak var scrollView: UIScrollView?
    private var target: CGPoint?
    private var completion: ((Bool) -> Void)?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    init(
        scrollView: UIScrollView,
        onActivityChanged: ((Bool) -> Void)? = nil,
        scroll: @escaping Scroll = { $0.setContentOffset($1, animated: $2) }
    ) {
        performScroll = scroll
        self.onActivityChanged = onActivityChanged
        self.scrollView = scrollView
    }

    /// Repeated animated requests share the current return. An immediate move replaces it.
    func scroll(to target: CGPoint, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated, isScrolling { return }
        cancel()
        guard let scrollView else {
            completion?(false)
            return
        }
        // Stop any UIKit motion before publishing the new target. Its synchronous
        // end callback belongs to the previous motion, not to this return.
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        self.target = target
        self.completion = completion
        isScrolling = true
        onActivityChanged?(true)
        guard animated, scrollView.window != nil, abs(scrollView.contentOffset.y - target.y) > 1 else {
            scrollView.setContentOffset(target, animated: false)
            finish(reachedTarget: true)
            return
        }
        performScroll(scrollView, target, true)
    }

    func waitUntilFinished() async -> Bool {
        guard isScrolling else { return true }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func scrollViewDidEndScrollingAnimation() {
        guard let scrollView, let target else { return }
        // UIKit can send this before willBeginDragging. An early end is cancellation,
        // never permission to start another animation or leave a waiter suspended.
        finish(
            reachedTarget: !scrollView.isTracking && !scrollView.isDragging
                && abs(scrollView.contentOffset.y - target.y) <= 1
        )
    }

    /// Gesture takeover already stops UIKit's animation; do not write its offset again.
    func cancel(stopsAnimation: Bool = true) {
        guard isScrolling else { return }
        let scrollView = scrollView
        finish(reachedTarget: false)
        if stopsAnimation, let scrollView {
            scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        }
    }

    private func finish(reachedTarget: Bool) {
        let wasScrolling = isScrolling
        isScrolling = false
        target = nil
        let completion = completion
        self.completion = nil
        let waiters = waiters
        self.waiters.removeAll()
        if wasScrolling { onActivityChanged?(false) }
        completion?(reachedTarget)
        for waiter in waiters {
            waiter.resume(returning: reachedTarget)
        }
    }
}
