//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol EntryViewerPagesDataSource: AnyObject {
    func getPageCount(for viewController: EntryViewerPagesVC) -> Int
    func getPage(index: Int, for viewController: EntryViewerPagesVC) -> UIViewController?
    func getPageIndex(of page: UIViewController, for viewController: EntryViewerPagesVC) -> Int?
}

final class EntryViewerPagesVC: UIViewController, Refreshable {

    @IBOutlet private weak var pageSelector: UISegmentedControl!
    @IBOutlet private weak var containerView: UIView!
    
    public weak var dataSource: EntryViewerPagesDataSource?

    private var isHistoryEntry = false
    private var canEditEntry = false
    private var entryIcon: UIImage?
    private var resolvedEntryTitle = ""
    private var isEntryExpired = false
    private var entryLastModificationTime = Date.distantPast
    
    private var titleView = DatabaseItemTitleView()
    
    private var pagesViewController: UIPageViewController! 
    private var currentPageIndex = 0 {
        didSet {
            if !isHistoryEntry {
                Settings.current.entryViewerPage = currentPageIndex
            }
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.titleView = titleView
        
        pagesViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil)
        pagesViewController.delegate = self
        if !ProcessInfo.isRunningOnMac {
            pagesViewController.dataSource = self
        }

        addChild(pagesViewController)
        pagesViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pagesViewController.view.frame = containerView.bounds
        containerView.addSubview(pagesViewController.view)
        pagesViewController.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        assert(dataSource != nil, "dataSource must be defined")
        refresh()
        if isHistoryEntry {
            switchTo(page: 0)
        } else {
            switchTo(page: Settings.current.entryViewerPage)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        navigationItem.rightBarButtonItem =
            pagesViewController.viewControllers?.first?.navigationItem.rightBarButtonItem
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refresh()
    }
    
    public func setContents(from entry: Entry, isHistoryEntry: Bool, canEditEntry: Bool) {
        entryIcon = UIImage.kpIcon(forEntry: entry)
        resolvedEntryTitle = entry.resolvedTitle
        isEntryExpired = entry.isExpired
        entryLastModificationTime = entry.lastModificationTime
        self.isHistoryEntry = isHistoryEntry
        self.canEditEntry = canEditEntry
        refresh()
    }
    
    public func switchTo(page index: Int) {
        guard let dataSource = dataSource,
              let targetPageVC = dataSource.getPage(index: index, for: self)
        else {
            assertionFailure()
            return
        }
        
        let direction: UIPageViewController.NavigationDirection
        if index >= currentPageIndex {
            direction = .forward
        } else {
            direction = .reverse
        }

        let previousPageVC = pagesViewController.viewControllers?.first
        previousPageVC?.willMove(toParent: nil)
        targetPageVC.willMove(toParent: pagesViewController)
        pagesViewController.setViewControllers(
            [targetPageVC],
            direction: direction,
            animated: !ProcessInfo.isRunningOnMac,
            completion: { [weak self] (finished) in
                self?.changeCurrentPage(from: previousPageVC, to: targetPageVC, index: index)
            }
        )
    }
    
    @IBAction func didChangePage(_ sender: Any) {
        switchTo(page: pageSelector.selectedSegmentIndex)
    }
    
    private func changeCurrentPage(
        from previousPageVC: UIViewController?,
        to targetPageVC: UIViewController,
        index: Int
    ) {
        previousPageVC?.didMove(toParent: nil)
        targetPageVC.didMove(toParent: pagesViewController)
        pageSelector.selectedSegmentIndex = index
        currentPageIndex = index
        navigationItem.rightBarButtonItem =
            targetPageVC.navigationItem.rightBarButtonItem
        
        let toolbarItems = targetPageVC.toolbarItems
        setToolbarItems(toolbarItems, animated: true)
    }
    
    func refresh() {
        guard isViewLoaded else { return }
        titleView.titleLabel.setText(resolvedEntryTitle, strikethrough: isEntryExpired)
        titleView.iconView.image = entryIcon
        if isHistoryEntry {
            if traitCollection.horizontalSizeClass == .compact {
                titleView.subtitleLabel.text = DateFormatter.localizedString(
                    from: entryLastModificationTime,
                    dateStyle: .medium,
                    timeStyle: .short)
            } else {
                titleView.subtitleLabel.text = DateFormatter.localizedString(
                    from: entryLastModificationTime,
                    dateStyle: .full,
                    timeStyle: .medium)
            }
            titleView.subtitleLabel.isHidden = false
        } else {
            titleView.subtitleLabel.isHidden = true
        }
        
        let currentPage = pagesViewController.viewControllers?.first
        (currentPage as? Refreshable)?.refresh()
    }
}

extension EntryViewerPagesVC: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard finished && completed else { return }

        guard let dataSource = dataSource,
              let selectedVC = pageViewController.viewControllers?.first,
              let selectedIndex = dataSource.getPageIndex(of: selectedVC, for: self)
        else {
            return
        }
        changeCurrentPage(
            from: previousViewControllers.first,
            to: selectedVC,
            index: selectedIndex)
    }
}

extension EntryViewerPagesVC: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = dataSource?.getPageIndex(of: viewController, for: self) else {
            return nil
        }
        return dataSource?.getPage(index: index - 1, for: self)
    }
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = dataSource?.getPageIndex(of: viewController, for: self) else {
            return nil
        }
        
        return dataSource?.getPage(index: index + 1, for: self)
    }
}
