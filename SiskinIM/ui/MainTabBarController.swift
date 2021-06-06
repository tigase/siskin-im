//
// MainTabBarController.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift
import Combine

class MainTabBarController: CustomTabBarController, UITabBarControllerDelegate {
    
    public static let RECENTS_TAB = 0;
    public static let ROSTER_TAB = 1;
    public static let MORE_TAB = 2;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        self.delegate = self;
        
        XmppService.instance.$connectedClients.map({ (XmppService.instance.clients.count - $0.count) + AccountManager.getAccounts().filter({(name)->Bool in
            return AccountSettings.LastError(name).getString() != nil
        }).count }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] value in
            self?.updateMoreBadge(count: value);
        }).store(in: &cancellables);
    }
    
    private func updateMoreBadge(count: Int) {
        self.tabBar.items![MainTabBarController.MORE_TAB].badgeValue = count == 0 ? nil : count.description;
        if count == 0 {
            NotificationManager.instance.updateApplicationIconBadgeNumber(completionHandler: nil);
        }
    }
        
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard viewController.restorationIdentifier == "SettingsNavigationControllerDummy" else {
            return true;
        }
        DispatchQueue.main.async {
            let controller = UIStoryboard(name: "Settings", bundle: nil).instantiateViewController(withIdentifier: "SettingsNavigationController")
            self.present(controller, animated: true, completion: nil);
        }
        return false;
    }
        
}
