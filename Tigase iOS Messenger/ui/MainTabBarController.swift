//
// MainTabBarController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import UIKit

class MainTabBarController: CustomTabBarController {
    
    open static let RECENTS_TAB = 0;
    open static let ROSTER_TAB = 1;
    open static let MORE_TAB = 2;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateMoreBadge), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil);
    }
    
    func updateMoreBadge(notification: Notification) {
        let xmppService = (notification.object as! XmppService);
        let count = xmppService.getClients(filter: {(client)->Bool in
            return client.state != .connected;
        }).count + AccountManager.getAccounts().filter({(name)->Bool in
            return AccountSettings.LastError(name).getString() != nil
        }).count;
        DispatchQueue.main.async {
            self.tabBar.items![MainTabBarController.MORE_TAB].badgeValue = count == 0 ? nil : count.description;
        }
    }
}