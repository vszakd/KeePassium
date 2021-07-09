//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

public protocol NavigationRouterDismissAttemptDelegate: AnyObject {
    func didAttemptToDismiss(navigationRouter: NavigationRouter)
}

public class NavigationRouter: NSObject {
    public typealias PopHandler = (() -> ())
    
    public private(set) var navigationController: UINavigationController
    private var popHandlers = [ObjectIdentifier: PopHandler]()
    private weak var oldDelegate: UINavigationControllerDelegate?

    weak var dismissAttemptDelegate: NavigationRouterDismissAttemptDelegate? = nil

    private var progressOverlay: ProgressOverlay?
    private var wasModalInPresentation = false
    private var wasNavigationBarUserInteractionEnabled = true
    private var oldNavigationBarAlpha = CGFloat(1.0)
    
    public var isModalInPresentation: Bool {
        get {
            guard #available(iOS 13, *) else {
                return false
            }
            return navigationController.isModalInPresentation
        }
        set {
            if #available(iOS 13, *) {
                navigationController.isModalInPresentation = newValue
            }
        }
    }
    
    public var isHorizontallyCompact: Bool {
        return navigationController.traitCollection.horizontalSizeClass == .compact
    }
    
    static func createModal(
        style: UIModalPresentationStyle,
        at popoverAnchor: PopoverAnchor? = nil
    ) -> NavigationRouter {
        let navVC = UINavigationController()
        let router = NavigationRouter(navVC)
        navVC.modalPresentationStyle = style
        navVC.presentationController?.delegate = router
        if let popover = navVC.popoverPresentationController {
            popoverAnchor?.apply(to: popover)
            popover.delegate = router
        }
        return router
    }

    init(_ navigationController: UINavigationController) {
        self.navigationController = navigationController
        oldDelegate = navigationController.delegate
        super.init()

        navigationController.delegate = self
    }
    
    deinit {
        navigationController.delegate = oldDelegate
    }
    
    public func dismiss(animated: Bool) {
        assert(navigationController.presentingViewController != nil)
        navigationController.dismiss(animated: animated, completion: { [self] in
            self.popAll(animated: animated)
        })
    }
    
    public func dismissModals(animated: Bool, completion: (()->())?) {
        guard navigationController.presentedViewController != nil else {
            return
        }
        navigationController.dismiss(animated: animated, completion: completion)
    }
    
    public func present(_ router: NavigationRouter, animated: Bool, completion: (()->Void)?) {
        navigationController.present(router, animated: animated, completion: completion)
    }
    

    public func present(
        _ viewController: UIViewController,
        animated: Bool,
        completion: (()->Void)?)
    {
        navigationController.present(viewController, animated: animated, completion: completion)
    }
    
    public func prepareCustomTransition(
        duration: CFTimeInterval = 0.5,
        type: CATransitionType = .fade,
        timingFunction: CAMediaTimingFunctionName = .linear
    ) {
        let transition = CATransition()
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: timingFunction)
        transition.type = type
        transition.isRemovedOnCompletion = true
        navigationController.view.layer.add(transition, forKey: kCATransition)
    }
    
    public func push(
        _ viewController: UIViewController,
        animated: Bool,
        replaceTopViewController: Bool = false,
        onPop popHandler: PopHandler?
    ) {
        if let popHandler = popHandler {
            let id = ObjectIdentifier(viewController)
            popHandlers[id] = popHandler
        }
        
        if replaceTopViewController,
           let topVC = navigationController.topViewController
        {
            var viewControllers = navigationController.viewControllers
            viewControllers[viewControllers.count - 1] = viewController
            navigationController.setViewControllers(viewControllers, animated: animated)
            triggerAndRemovePopHandler(for: topVC)
        } else {
            navigationController.pushViewController(viewController, animated: animated)
        }
    }
    
    public func resetRoot(
        _ viewController: UIViewController,
        animated: Bool,
        onPop popHandler: PopHandler?
    ) {
        popToRoot(animated: animated)
        let oldRootVC = navigationController.viewControllers.first
        navigationController.setViewControllers([viewController], animated: animated)
        if oldRootVC != nil {
            triggerAndRemovePopHandler(for: oldRootVC!)
        }
    }
    
    public func pop(animated: Bool, completion: (()->Void)? = nil) {
        let isLastVC = (navigationController.viewControllers.count == 1)
        if isLastVC {
            navigationController.dismiss(animated: animated, completion: completion)
            triggerAndRemovePopHandler(for: navigationController.topViewController!) 
        } else {
            navigationController.popViewController(animated: animated, completion: completion)
        }
    }
    
    public func popTo(viewController: UIViewController, animated: Bool) {
        navigationController.popToViewController(viewController, animated: animated)
    }
    
    public func pop(viewController: UIViewController, animated: Bool) {
        let isPushed = navigationController.viewControllers.contains(viewController)
        guard isPushed else {
            return
        }
        popTo(viewController: viewController, animated: animated)
        pop(animated: animated) 
    }
    
    public func popToRoot(animated: Bool) {
        navigationController.popToRootViewController(animated: animated)
    }
    
    fileprivate func popAll(animated: Bool) {
        popToRoot(animated: animated)
        pop(animated: animated) 
    }
    
    fileprivate func triggerAndRemovePopHandler(for viewController: UIViewController) {
        let id = ObjectIdentifier(viewController)
        if let popHandler = popHandlers[id] {
            popHandler(viewController)
            popHandlers.removeValue(forKey: id)
        }
    }
}

extension NavigationRouter: UINavigationControllerDelegate {
    public func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool)
    {
        guard let fromVC = navigationController.transitionCoordinator?.viewController(forKey: .from),
            !navigationController.viewControllers.contains(fromVC)
            else { return }
        triggerAndRemovePopHandler(for: fromVC)
        oldDelegate?.navigationController?(
            navigationController,
            didShow: viewController,
            animated: animated)
    }
    
    public func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool)
    {
        let shouldShowToolbar = (viewController.toolbarItems?.count ?? 0) > 0
        navigationController.setToolbarHidden(!shouldShowToolbar, animated: animated)
    }
}

extension NavigationRouter: UIPopoverPresentationControllerDelegate {
    public func presentationController(
        _ controller: UIPresentationController,
        viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle
    ) -> UIViewController?
    {
        return nil // "keep existing"
    }
}

extension NavigationRouter: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidAttemptToDismiss(
        _ presentationController: UIPresentationController
    ) {
        dismissAttemptDelegate?.didAttemptToDismiss(navigationRouter: self)
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        popAll(animated: false)
    }
}


extension NavigationRouter: ProgressViewHost {
    public func showProgressView(title: String, allowCancelling: Bool) {
        showProgressView(title: title, allowCancelling: allowCancelling, animated: true)
    }
    public func showProgressView(title: String, allowCancelling: Bool, animated: Bool) {
        if progressOverlay != nil {
            progressOverlay?.title = title
            progressOverlay?.isCancellable = allowCancelling
            return
        }
        progressOverlay = ProgressOverlay.addTo(
            navigationController.view,
            title: title,
            animated: animated)
        progressOverlay?.isCancellable = allowCancelling
        if #available(iOS 13, *) {
            wasModalInPresentation = navigationController.isModalInPresentation
            navigationController.isModalInPresentation = true
        }

        let navigationBar = navigationController.navigationBar
        oldNavigationBarAlpha = navigationBar.alpha
        wasNavigationBarUserInteractionEnabled = navigationBar.isUserInteractionEnabled
        navigationBar.isUserInteractionEnabled = false
        if animated {
            UIView.animate(withDuration: 0.3) {
                navigationBar.alpha = 0.1
            }
        } else {
            navigationBar.alpha = 0.1
        }
    }
    
    public func updateProgressView(with progress: ProgressEx) {
        progressOverlay?.update(with: progress)
    }
    
    public func hideProgressView() {
        hideProgressView(animated: true)
    }
    
    public func hideProgressView(animated: Bool) {
        guard progressOverlay != nil else { return }
        let navigationBar = navigationController.navigationBar
        if animated {
            UIView.animate(withDuration: 0.3) { [oldNavigationBarAlpha] in
                navigationBar.alpha = oldNavigationBarAlpha
            }
        } else {
            navigationBar.alpha = oldNavigationBarAlpha
        }
        navigationBar.isUserInteractionEnabled = wasNavigationBarUserInteractionEnabled
        
        if #available(iOS 13, *) {
            navigationController.isModalInPresentation = wasModalInPresentation
        }
        progressOverlay?.dismiss(animated: animated) {
            [weak self] (finished) in
            guard let self = self else { return }
            self.progressOverlay?.removeFromSuperview()
            self.progressOverlay = nil
        }
    }
}

extension UIViewController {
    func present(_ router: NavigationRouter, animated: Bool, completion: (()->Void)?) {
        present(router.navigationController, animated: animated, completion: completion)
    }
}

extension UINavigationController {
    func popViewController(animated: Bool, completion: (()->Void)?) {
        popViewController(animated: animated)
        
        guard animated, let transitionCoordinator = transitionCoordinator else {
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        transitionCoordinator.animate(alongsideTransition: nil) { _ in
            completion?()
        }
    }
}
