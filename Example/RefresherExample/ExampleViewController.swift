// Created by weixi on 2026/09/20.

import Combine
import Refresher
import UIKit

final class ExampleViewController: UIViewController, UITableViewDataSource, UICollectionViewDataSource {
    private struct Item {
        let title: String
        let subtitle: String
    }

    private enum DemoFailure: Error { case requested }
    private let table = UITableView(frame: .zero, style: .plain)
    private lazy var grid: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            item.contentInsets = .init(
                top: 6,
                leading: 6,
                bottom: 6,
                trailing: 6
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(116)),
                repeatingSubitem: item,
                count: 2
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(
                top: 8,
                leading: 10,
                bottom: 8,
                trailing: 10
            )
            return section
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        view.backgroundColor = .systemGroupedBackground
        return view
    }()

    private let mode = UISegmentedControl(items: ["List", "Grid"])
    private let summary = UILabel()
    private let status = UILabel()
    private let notice = UILabel()
    private let container = UIView()
    private let attachButton = UIButton(type: .system)
    private var controller: RefreshController?
    private var subscription: AnyCancellable?
    private var items: [Item] = []
    private var generation = 0
    private var refreshes = 0
    private var pages = 0
    private var failNext = false
    private var slowNext = false
    private var isGrid = false
    private let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
    private var scrollView: UIScrollView {
        isGrid ? grid : table
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Refresher"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Refresh",
            style: .plain,
            target: self,
            action: #selector(refresh)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "refresh"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "cancel"
        configureControls()
        table.dataSource = self
        table.rowHeight = 68
        table.accessibilityIdentifier = "list"
        table.backgroundColor = .systemBackground
        grid.dataSource = self
        grid.accessibilityIdentifier = "grid"
        replaceItems(count: 24)
        showScrollView()
        attach()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        controller?.contentDidChange()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller?.contentDidChange()
    }

    private func configureControls() {
        mode.selectedSegmentIndex = 0
        mode.accessibilityIdentifier = "mode"
        mode.addTarget(
            self,
            action: #selector(changeMode),
            for: .valueChanged
        )
        summary.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        summary.accessibilityIdentifier = "summary"
        summary.textColor = .secondaryLabel
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.accessibilityIdentifier = "state"
        notice.font = .preferredFont(forTextStyle: .footnote)
        notice.textColor = .secondaryLabel
        notice.numberOfLines = 2
        notice.text = "Pull down to refresh. Scroll to the end for another page."
        notice.accessibilityIdentifier = "notice"
        let controls = UIStackView(arrangedSubviews: [mode, summary, status, notice])
        controls.axis = .vertical
        controls.spacing = 10
        let firstRow = UIStackView(arrangedSubviews: [
            button(
                "Load page",
                id: "loadMore",
                action: #selector(loadMore)
            ),
            button(
                "Fail next",
                id: "failNext",
                action: #selector(setFailure)
            ),
            button(
                "Slow next",
                id: "slowNext",
                action: #selector(setSlow)
            ),
        ])
        let secondRow = UIStackView(arrangedSubviews: [
            button(
                "Short list",
                id: "short",
                action: #selector(shortList)
            ),
            button(
                "Reset",
                id: "reset",
                action: #selector(reset)
            ),
            attachButton,
        ])
        attachButton.setTitle("Detach", for: .normal)
        attachButton.accessibilityIdentifier = "attachment"
        attachButton.addTarget(
            self,
            action: #selector(toggleAttachment),
            for: .touchUpInside
        )
        for row in [firstRow, secondRow] {
            row.distribution = .fillEqually
            row.spacing = 8
            controls.addArrangedSubview(row)
        }
        view.addSubview(controls)
        view.addSubview(container)
        controls.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func button(
        _ title: String,
        id: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.buttonSize = .small
        button.configuration = configuration
        button.accessibilityIdentifier = id
        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )
        return button
    }

    private func showScrollView() {
        table.removeFromSuperview()
        grid.removeFromSuperview()
        let scrollView = scrollView
        container.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func attach() {
        let controller = RefreshController(
            scrollView: scrollView,
            loadMoreAvailability: items.count >= 60 ? .exhausted : .ready,
            onRefresh: { [weak self] in try await self?.performRefresh() },
            onLoadMore: { [weak self] in try await self?.performPage() }
        )
        self.controller = controller
        subscription = controller.states.sink { [weak self] state in
            self?.status.text = "Refresh: \(Self.name(state.refresh)) · Page: \(Self.name(state.loadMore))"
        }
        attachButton.setTitle("Detach", for: .normal)
        controller.contentDidChange()
    }

    private func performRefresh() async throws {
        do {
            try await delay()
            try Task.checkCancellation()
            generation += 1
            refreshes += 1
            replaceItems(count: 24)
            controller?.loadMoreAvailability = .ready
            notice.text = "Refreshed. Pull again whenever you need."
        } catch {
            if !(error is CancellationError) { notice.text = "Refresh failed. Pull again or tap Refresh." }
            throw error
        }
    }

    private func performPage() async throws {
        do {
            try await delay()
            try Task.checkCancellation()
            pages += 1
            let count = min(12, 60 - items.count)
            appendItems(count: count)
            controller?.loadMoreAvailability = items.count >= 60 ? .exhausted : .ready
            notice.text = items.count >= 60 ? "All 60 items loaded." : "Page added. Keep scrolling."
        } catch {
            if !(error is CancellationError) { notice.text = "Page failed. Drag again or tap Load page." }
            throw error
        }
    }

    private func delay() async throws {
        let fail = failNext
        let slow = slowNext
        failNext = false
        slowNext = false
        let seconds: Double = slow ? 3 : (testing ? 0.15 : 0.8)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if fail { throw DemoFailure.requested }
    }

    private func replaceItems(count: Int) {
        items.removeAll()
        appendItems(count: count)
    }

    private func appendItems(count: Int) {
        let start = items.count
        items += (start ..< start + count).map {
            Item(title: "Item \($0 + 1)", subtitle: "Edition \(generation + 1) · A fresh perspective")
        }
        table.reloadData()
        grid.reloadData()
        scrollView.layoutIfNeeded()
        summary.text = "Items \(items.count) · Refreshes \(refreshes) · Pages \(pages)"
        controller?.contentDidChange()
    }

    @objc private func refresh() {
        controller?.refresh()
    }

    @objc private func loadMore() {
        controller?.loadMore()
    }

    @objc private func cancel() {
        controller?.cancel()
        notice.text = "Cancelled. The next request can start immediately."
    }

    @objc private func setFailure() {
        failNext = true
        notice.text = "The next request will fail once."
    }

    @objc private func setSlow() {
        slowNext = true
        notice.text = "The next request takes 3 seconds. Try Cancel or Detach."
    }

    @objc private func changeMode() {
        controller?.detach()
        controller = nil
        isGrid = mode.selectedSegmentIndex == 1
        showScrollView()
        view.layoutIfNeeded()
        attach()
    }

    @objc private func shortList() {
        controller?.cancel()
        controller?.isActive = false
        replaceItems(count: 2)
        controller?.loadMoreAvailability = .ready
        controller?.reset()
        controller?.isActive = true
        controller?.contentDidChange()
        notice.text = "Short content fills automatically while more items are available."
    }

    @objc private func reset() {
        controller?.cancel()
        controller?.isActive = false
        refreshes = 0
        pages = 0
        generation = 0
        failNext = false
        slowNext = false
        replaceItems(count: 24)
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
        controller?.loadMoreAvailability = .ready
        controller?.reset()
        controller?.isActive = true
        controller?.contentDidChange()
        notice.text = "Pull down to refresh. Scroll to the end for another page."
    }

    @objc private func toggleAttachment() {
        if let controller {
            controller.detach()
            self.controller = nil
            subscription = nil
            attachButton.setTitle("Attach", for: .normal)
            status.text = "Detached"
        } else {
            attach()
        }
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "item")
        configure(cell: cell, item: items[indexPath.item])
        return cell
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = items[indexPath.item].title
        content.secondaryText = items[indexPath.item].subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundConfiguration = .listGroupedCell()
        cell.layer.cornerRadius = 14
        cell.clipsToBounds = true
        return cell
    }

    private func configure(cell: UITableViewCell, item: Item) {
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = item.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "waveform.circle.fill")
        content.imageProperties.tintColor = .systemTeal
        cell.contentConfiguration = content
        cell.selectionStyle = .none
    }

    private static func name(_ state: RefreshState?) -> String {
        switch state {
        case .idle, nil: "idle"
        case .pulling: "pulling"
        case .refreshing: "loading"
        case .finishing: "finishing"
        }
    }

    private static func name(_ state: LoadMoreState?) -> String {
        switch state {
        case .idle: "ready"
        case .loading: "loading"
        case .exhausted: "done"
        case .unavailable, nil: "off"
        }
    }
}
