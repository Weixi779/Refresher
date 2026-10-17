// Created by weixi on 2026/09/20.

import UIKit

@MainActor
final class ScrollBinding {
    enum Change {
        case geometry
        case pan(UIGestureRecognizer.State)
        case scrollingAnimationEnded
    }

    struct Geometry {
        let contentHeight: CGFloat
        let viewportHeight: CGFloat
        let pullDistance: CGFloat
        let distanceToBottom: CGFloat
        let isMounted: Bool
    }

    typealias Animate = @MainActor (
        _ duration: TimeInterval,
        _ curve: UIView.AnimationCurve,
        _ changes: @escaping () -> Void,
        _ completion: @escaping () -> Void
    ) -> (any RefreshAnimation)?

    weak var scrollView: UIScrollView?
    var onChange: ((Change) -> Void)?
    private let header: (any RefreshHeader)?
    private let headerViewport = UIView()
    private let footer: (any LoadMoreFooter)?
    private let configuration: RefreshController.Configuration
    private let animate: Animate
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private var observations: [NSKeyValueObservation] = []
    private var animation: (any RefreshAnimation)?
    private var completionDelayTask: Task<Void, Error>?
    private var completionDelayConsumed = false
    private var finishTask: Task<Void, Never>?
    private let returnController: ScrollToTopController
    private var returnWasInterrupted = false
    private var returnedForRefresh = false
    private var showsRefreshIndicator = true
    private var topContribution: CGFloat = 0
    private var bottomContribution: CGFloat = 0
    private let originalBounce: Bool

    init(
        scrollView: UIScrollView,
        header: (any RefreshHeader)?,
        footer: (any LoadMoreFooter)?,
        configuration: RefreshController.Configuration,
        animate: @escaping Animate = ScrollBinding.animate,
        scroll: @escaping ScrollToTopController.Scroll = { $0.setContentOffset($1, animated: $2) },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.scrollView = scrollView
        returnController = ScrollToTopController(scrollView: scrollView, onActivityChanged: configuration.onReturnActivityChanged, scroll: scroll)
        self.header = header
        self.footer = footer
        self.configuration = configuration
        self.animate = animate
        self.sleep = sleep
        originalBounce = scrollView.alwaysBounceVertical
        if header != nil { scrollView.alwaysBounceVertical = true }
        if let header {
            headerViewport.clipsToBounds = true
            headerViewport.isUserInteractionEnabled = false
            scrollView.addSubview(headerViewport)
            headerViewport.addSubview(header)
        }
        if let footer { scrollView.addSubview(footer) }
        layout()
        observe(scrollView)
    }

    var refreshOriginProvider: (() -> CGFloat?)?

    var refreshOriginOffsetY: CGFloat? {
        if let refreshOriginProvider { return refreshOriginProvider() }
        return scrollView.map { -($0.adjustedContentInset.top - topContribution) }
    }

    var geometry: Geometry {
        guard let scrollView else {
            return Geometry(
                contentHeight: 0,
                viewportHeight: 0,
                pullDistance: 0,
                distanceToBottom: .infinity,
                isMounted: false
            )
        }
        let baseTop = -(refreshOriginOffsetY ?? -scrollView.adjustedContentInset.top)
        let baseBottom = scrollView.adjustedContentInset.bottom - bottomContribution
        return Geometry(
            contentHeight: scrollView.contentSize.height,
            viewportHeight: scrollView.bounds.height,
            pullDistance: max(0, -(scrollView.contentOffset.y + baseTop)),
            distanceToBottom: scrollView.contentSize.height + baseBottom
                - scrollView.contentOffset.y - scrollView.bounds.height,
            isMounted: scrollView.window != nil
        )
    }

    func layout() {
        guard let scrollView else { return }
        // Only the gap below the resting content origin belongs to refresh.
        // Animate this viewport with the offset so the header cannot cross the chrome.
        let pull = geometry.pullDistance
        // Keep the origin signed, even when the viewport is empty. Clamping it
        // to zero would animate the clip through the chrome on a distant return.
        let viewportY = scrollView.contentOffset.y - (refreshOriginOffsetY ?? -scrollView.adjustedContentInset.top)
        let viewportFrame = CGRect(x: 0, y: viewportY, width: scrollView.bounds.width, height: pull)
        if headerViewport.frame != viewportFrame { headerViewport.frame = viewportFrame }
        let headerFrame = CGRect(
            x: 0,
            y: -viewportY - configuration.refreshHeight,
            width: scrollView.bounds.width,
            height: configuration.refreshHeight
        )
        let footerFrame = CGRect(
            x: 0,
            y: scrollView.contentSize.height,
            width: scrollView.bounds.width,
            height: configuration.loadMoreHeight
        )
        if header?.frame != headerFrame { header?.frame = headerFrame }
        if footer?.frame != footerFrame { footer?.frame = footerFrame }
    }

    func render(_ state: LoadingState) {
        if let phase = state.refresh {
            let displayedPhase: RefreshState = showsRefreshIndicator ? phase : .idle
            header?.isHidden = displayedPhase == .idle
            if displayedPhase != .finishing { header?.alpha = 1 }
            header?.render(displayedPhase)
        }
        if let phase = state.loadMore {
            let visible = footer != nil && (phase == .idle || phase == .loading)
            setBottomContribution(visible ? configuration.loadMoreHeight : 0)
            footer?.isHidden = !visible
            footer?.render(phase)
        }
    }

    func beginRefresh(reveal: Bool, showsIndicator: Bool = true, scrollToTop: Bool = false) {
        interruptAnimation()
        completionDelayConsumed = false
        showsRefreshIndicator = showsIndicator
        returnWasInterrupted = false
        guard showsIndicator, let scrollView, let origin = refreshOriginOffsetY else { return }
        let wasNearTop = scrollView.contentOffset.y <= origin + 1
        let offset = scrollView.contentOffset
        // Reserve the header without moving the position the user released at.
        UIView.performWithoutAnimation {
            setTopContribution(configuration.refreshHeight)
            scrollView.setContentOffset(offset, animated: false)
        }
        guard scrollToTop || wasNearTop else { return }
        let target = CGPoint(x: offset.x, y: origin - configuration.refreshHeight)
        if scrollToTop {
            startReturn(to: target, animated: configuration.animationDuration > 0)
            return
        }
        animation = animate(
            configuration.animationDuration,
            reveal ? .easeInOut : .easeOut,
            { [weak scrollView] in scrollView?.setContentOffset(target, animated: false) },
            {}
        )
    }

    func scrollToTopDuringRefresh() {
        scrollToTop(animated: configuration.animationDuration > 0)
    }

    func scrollToTop(animated: Bool) {
        if animated, returnController.isScrolling { return }
        guard let scrollView, let origin = refreshOriginOffsetY else { return }
        if !animated || animation?.isActive == true { interruptAnimation() }
        startReturn(to: CGPoint(x: scrollView.contentOffset.x, y: origin - topContribution), animated: animated)
    }

    private func startReturn(to target: CGPoint, animated: Bool) {
        returnWasInterrupted = false
        returnedForRefresh = topContribution > 0
        returnController.scroll(to: target, animated: animated) { [weak self] reached in
            guard let self, !reached else { return }
            returnedForRefresh = false
            returnWasInterrupted = true
        }
    }

    func prepareForRefreshContentUpdate() async throws {
        if returnWasInterrupted {
            // Takeover ends automatic scrolling, not our responsibility to remove
            // the refresh inset before a replacement snapshot can clamp the list.
            restoreTop()
            return
        }
        guard returnController.isScrolling || returnedForRefresh else { return }
        try await waitBeforeClosing()
        if !returnWasInterrupted, let scrollView, let origin = refreshOriginOffsetY {
            // Keep the outward target stable, then close before a replacement/empty
            // snapshot can clamp the list against the refresh inset.
            startReturn(
                to: CGPoint(x: scrollView.contentOffset.x, y: origin),
                animated: configuration.animationDuration > 0
            )
            _ = await returnController.waitUntilFinished()
            try Task.checkCancellation()
        }
        returnedForRefresh = false
        restoreTop()
    }

    func finishRefresh(completion: @escaping () -> Void) {
        guard showsRefreshIndicator else {
            completion()
            return
        }
        guard returnController.isScrolling || animation?.isActive == true
            || (!completionDelayConsumed && configuration.refreshCompletionDelay > 0 && topContribution > 0) else {
            closeRefresh(completion: completion)
            return
        }
        // A fast request must not cut the release animation short. Keep the request
        // concurrent, then give the refreshed content its configured pause before closing.
        finishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await waitBeforeClosing()
            } catch {
                return
            }
            finishTask = nil
            closeRefresh(completion: completion)
        }
    }

    /// Shared by successful content preparation and the failure/completion path.
    /// The pause starts after both the response and the current reveal have finished.
    private func waitBeforeClosing() async throws {
        _ = await returnController.waitUntilFinished()
        if let animation, animation.isActive {
            await withCheckedContinuation { continuation in
                animation.whenFinished { _ in continuation.resume() }
            }
        }
        try Task.checkCancellation()
        guard !completionDelayConsumed else { return }
        completionDelayConsumed = true
        guard !returnWasInterrupted, topContribution > 0, configuration.refreshCompletionDelay > 0 else { return }
        let delay = configuration.refreshCompletionDelay
        let task = Task { try await sleep(delay) }
        completionDelayTask = task
        // Gesture takeover/leave cancels only this pause; cancellation of the
        // refresh operation must still propagate before any content is applied.
        _ = await task.result
        try Task.checkCancellation()
        _ = await returnController.waitUntilFinished()
        try Task.checkCancellation()
    }

    private func closeRefresh(completion: @escaping () -> Void) {
        guard topContribution > 0 else {
            completion()
            return
        }
        if returnWasInterrupted || scrollView?.isTracking == true || scrollView?.isDragging == true {
            restoreTop()
            completion()
            return
        }
        if returnedForRefresh, let scrollView, let origin = refreshOriginOffsetY {
            startReturn(
                to: CGPoint(x: scrollView.contentOffset.x, y: origin),
                animated: configuration.animationDuration > 0
            )
            finishTask = Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await returnController.waitUntilFinished()
                guard !Task.isCancelled else { return }
                finishTask = nil
                returnedForRefresh = false
                restoreTop()
                completion()
            }
            return
        }
        interruptAnimation()
        animation = animate(
            configuration.animationDuration,
            .easeInOut,
            { [weak self] in
                self?.restoreTop()
                self?.header?.alpha = 0
            },
            completion
        )
    }

    func didFinishRefresh() {
        returnedForRefresh = false
        returnWasInterrupted = false
        animation = nil
        showsRefreshIndicator = true
    }

    func cancelRefresh() {
        returnedForRefresh = false
        completionDelayTask?.cancel()
        completionDelayTask = nil
        finishTask?.cancel()
        finishTask = nil
        interruptAnimation()
        showsRefreshIndicator = true
        restoreTop()
    }

    func interruptAnimation(gestureTakeover: Bool = false) {
        if gestureTakeover {
            completionDelayTask?.cancel()
            returnedForRefresh = false
            returnWasInterrupted = true
        }
        let interruptedAnimation = animation
        animation = nil
        // Keep the visible position and settle any pending refresh completion.
        interruptedAnimation?.cancel()
        returnController.cancel(stopsAnimation: !gestureTakeover)
    }

    func endReturn(interrupted: Bool) {
        if interrupted {
            completionDelayTask?.cancel()
            returnWasInterrupted = true
            returnedForRefresh = false
            returnController.cancel()
        } else {
            returnController.scrollViewDidEndScrollingAnimation()
        }
    }

    func detach() {
        observations.removeAll()
        onChange = nil
        cancelRefresh()
        setBottomContribution(0)
        header?.removeFromSuperview()
        headerViewport.removeFromSuperview()
        footer?.removeFromSuperview()
        if header != nil, scrollView?.alwaysBounceVertical == true {
            scrollView?.alwaysBounceVertical = originalBounce
        }
        scrollView = nil
    }

    private func restoreTop() {
        guard let scrollView else { return }
        // Preserve other owners' inset changes; close only our own overscroll gap.
        let ownedTop = topContribution
        let offset = scrollView.contentOffset
        setTopContribution(0)
        guard ownedTop > 0 else { return }
        if scrollView.isTracking || scrollView.isDragging {
            scrollView.contentOffset = offset
        } else if scrollView.contentOffset.y < -scrollView.adjustedContentInset.top {
            scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
        }
    }

    private func setTopContribution(_ value: CGFloat) {
        guard let scrollView, value != topContribution else { return }
        let delta = value - topContribution
        topContribution = value
        scrollView.contentInset.top += delta
    }

    private func setBottomContribution(_ value: CGFloat) {
        guard let scrollView, value != bottomContribution else { return }
        let delta = value - bottomContribution
        bottomContribution = value
        scrollView.contentInset.bottom += delta
    }

    private func observe(_ scrollView: UIScrollView) {
        func observe<Value>(_ keyPath: KeyPath<UIScrollView, Value>) -> NSKeyValueObservation {
            scrollView.observe(keyPath, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    // State-machine events may be queued; geometry must join the
                    // same UIKit animation transaction as the content offset.
                    self?.layout()
                    self?.onChange?(.geometry)
                }
            }
        }
        observations = [
            observe(\.contentOffset),
            observe(\.contentSize),
            observe(\.bounds),
            observe(\.contentInset),
            observe(\.adjustedContentInset),
        ]
        observations.append(scrollView.panGestureRecognizer.observe(\.state, options: [.new]) { [weak self] pan, _ in
            MainActor.assumeIsolated { self?.onChange?(.pan(pan.state)) }
        })
    }

    private static func animate(
        duration: TimeInterval,
        curve: UIView.AnimationCurve,
        changes: @escaping () -> Void,
        completion: @escaping () -> Void
    ) -> (any RefreshAnimation)? {
        guard duration > 0 else {
            changes()
            completion()
            return nil
        }
        return NativeRefreshAnimation(duration: duration, curve: curve, changes: changes, completion: completion)
    }
}
