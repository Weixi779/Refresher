// Created by weixi on 2026/09/20.

import UIKit

public final class DefaultRefreshHeader: UIView, RefreshHeader {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let arrow = UIImageView(image: UIImage(systemName: "arrow.down"))

    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        arrow.tintColor = .secondaryLabel
        arrow.contentMode = .scaleAspectFit
        addSubview(arrow)
        addSubview(spinner)
        accessibilityIdentifier = "refresher.header"
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        arrow.bounds = CGRect(
            x: 0,
            y: 0,
            width: 20,
            height: 24
        )
        arrow.center = spinner.center
    }

    public func render(_ state: RefreshState) {
        switch state {
        case .idle:
            spinner.stopAnimating()
            arrow.isHidden = true
            accessibilityLabel = nil
        case let .pulling(progress):
            spinner.stopAnimating()
            arrow.isHidden = false
            arrow.transform = CGAffineTransform(rotationAngle: progress >= 1 ? .pi : 0)
            accessibilityLabel = progress >= 1 ? "Release to refresh" : "Pull to refresh"
        case .refreshing, .finishing:
            arrow.isHidden = true
            spinner.startAnimating()
            accessibilityLabel = "Refreshing"
        }
    }
}

public final class DefaultLoadMoreFooter: UIView, LoadMoreFooter {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = "No more items"
        addSubview(label)
        addSubview(spinner)
        accessibilityIdentifier = "refresher.footer"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        label.frame = bounds.insetBy(dx: 16, dy: 0)
    }

    public func render(_ state: LoadMoreState) {
        label.isHidden = state != .exhausted
        if state == .loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}
