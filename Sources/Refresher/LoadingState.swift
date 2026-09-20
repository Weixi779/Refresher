// Created by weixi on 2026/09/20.

import UIKit

public enum RefreshState: Equatable {
    case idle
    case pulling(progress: CGFloat)
    case refreshing
    case finishing
}

public enum LoadMoreState: Equatable {
    case unavailable
    case idle
    case loading
    case exhausted
}

public enum LoadMoreAvailability: Equatable {
    case unavailable
    case ready
    case exhausted
}

/// Pulling a header and loading a page can coexist.
public struct LoadingState: Equatable {
    public let refresh: RefreshState?
    public let loadMore: LoadMoreState?
}

@MainActor
public protocol RefreshHeader: UIView {
    func render(_ state: RefreshState)
}

@MainActor
public protocol LoadMoreFooter: UIView {
    func render(_ state: LoadMoreState)
}
