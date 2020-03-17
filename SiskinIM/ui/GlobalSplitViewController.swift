//
// GlobalSplitViewController.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//


import UIKit

class GlobalSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    
//    override var preferredStatusBarStyle: UIStatusBarStyle {
//        return Appearance.current.isDark ? .lightContent : .default;
//    }

    override func viewDidLoad() {
        super.viewDidLoad();
        self.delegate = self;
    }
    
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool{
        return true
    }
 
    func splitViewController(_ splitViewController: UISplitViewController, showDetail detailvc: UIViewController, sender: Any?) -> Bool {
        let mastervc = splitViewController.viewControllers[0] as! UITabBarController;
        if splitViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClass.compact {
//            mastervc.selectedViewController?.showViewController(detailvc, sender: sender);
            if let detail = detailvc as? UINavigationController {
                (mastervc.selectedViewController as? UINavigationController)?.pushViewController(detail.viewControllers[0], animated: true);
            } else {
                (mastervc.selectedViewController as? UINavigationController)?.pushViewController(detailvc, animated: true);
            }
        } else {
            splitViewController.viewControllers = [mastervc, detailvc];
        }
        return true;
    }
    
    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        let mastervc = splitViewController.viewControllers[0] as! UITabBarController;
        if let uinav = mastervc.selectedViewController as? UINavigationController {
            if uinav.viewControllers.count > 1 {
                return uinav.popViewController(animated: false);
            }
        }
        return nil;
    }
    
}
