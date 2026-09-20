// Created by weixi on 2026/09/20.

import UIKit

@MainActor
final class ScrollBinding {
    enum Change {
        case geometry
        case pan(UIGestureRecognizer.State)
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
        _ changes: @escaping () -> Void,
        _ completion: @escaping () -> Void
    ) -> UIViewPropertyAnimator?

    weak var scrollView: UIScrollView?
    var onChange: ((Change) -> Void)?
    private let header: (any RefreshHeader)?
    private let footer: (any LoadMoreFooter)?
    private let configuration: RefreshController.Configuration
    private let animate: Animate
    private var observations: [NSKeyValueObservation] = []
    private var animation: UIViewPropertyAnimator?
    private var topContribution: CGFloat = 0
    private var bottomContribution: CGFloat = 0
    private let originalBounce: Bool

    init(
        scrollView: UIScrollView,
        header: (any RefreshHeader)?,
        footer: (any LoadMoreFooter)?,
        configuration: RefreshController.Configuration,
        animate: @escaping Animate = ScrollBinding.animate
    ) {
        self.scrollView = scrollView
        self.header = header
        self.footer = footer
        self.configuration = configuration
        self.animate = animate
        originalBounce = scrollView.alwaysBounceVertical
        if header != nil { scrollView.alwaysBounceVertical = true }
        if let header { scrollView.addSubview(header) }
        if let footer { scrollView.addSubview(footer) }
        layout()
        observe(scrollView)
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
        let baseTop = scrollView.adjustedContentInset.top - topContribution
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
        let headerFrame = CGRect(
            x: 0,
            y: -configuration.refreshHeight,
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
            header?.isHidden = phase == .idle
            header?.render(phase)
        }
        if let phase = state.loadMore {
            let visible = phase != .unavailable
            setBottomContribution(visible ? configuration.loadMoreHeight : 0)
            footer?.isHidden = !visible
            footer?.render(phase)
        }
    }

    func beginRefresh(reveal: Bool) {
        animation?.stopAnimation(true)
        animation = nil
        guard let scrollView else { return }
        let wasNearTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1
        setTopContribution(configuration.refreshHeight)
        if reveal, wasNearTop {
            scrollView.setContentOffset(CGPoint(
                x: scrollView.contentOffset.x,
                y: -scrollView.adjustedContentInset.top
            ), animated: false)
        }
    }

    func finishRefresh(completion: @escaping () -> Void) {
        animation?.stopAnimation(true)
        animation = animate(
            configuration.animationDuration,
            { [weak self] in
                self?.restoreTop()
            },
            completion
        )
    }

    func didFinishRefresh() {
        animation = nil
    }

    func cancelRefresh() {
        animation?.stopAnimation(true)
        animation = nil
        restoreTop()
    }

    func detach() {
        observations.removeAll()
        onChange = nil
        cancelRefresh()
        setBottomContribution(0)
        header?.removeFromSuperview()
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
        setTopContribution(0)
        if ownedTop > 0, scrollView.contentOffset.y < -scrollView.adjustedContentInset.top {
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
                MainActor.assumeIsolated { self?.onChange?(.geometry) }
            }
        }
        observations = [
            observe(\.contentOffset),
            observe(\.contentSize),
            observe(\.bounds),
            observe(\.contentInset),
            observe(\.adjustedContentInset)
        ]
        observations.append(scrollView.panGestureRecognizer.observe(\.state, options: [.new]) { [weak self] pan, _ in
            MainActor.assumeIsolated { self?.onChange?(.pan(pan.state)) }
        })
    }

    private static func animate(
        duration: TimeInterval,
        changes: @escaping () -> Void,
        completion: @escaping () -> Void
    ) -> UIViewPropertyAnimator? {
        guard duration > 0 else {
            changes()
            completion()
            return nil
        }
        let animator = UIViewPropertyAnimator(
            duration: duration,
            curve: .easeOut,
            animations: changes
        )
        animator.addCompletion { _ in completion() }
        animator.startAnimation()
        return animator
    }
}
