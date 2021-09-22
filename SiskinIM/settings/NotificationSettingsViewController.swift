//
// NotificationSettingsViewController.swift
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
import Combine

class NotificationSettingsViewController: UITableViewController {
    
    private var cancellables: Set<AnyCancellable> = [];
    
    private var items: [[SettingsEnum]] = [[.pushNotifications],[.notificationsFromUnknown]];
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return items.count;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items[section].count;
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            if UIApplication.shared.isRegisteredForRemoteNotifications {
                return NSLocalizedString("If enabled, you will receive notifications of new messages or calls even if SiskinIM is in background. SiskinIM servers will forward those notifications for you from XMPP servers.", comment: "push notifications option description");
            } else {
                return NSLocalizedString("You need to allow application to show notifications and for background refresh.", comment: "push notifications not allowed warning")
            }
        case 1:
            return NSLocalizedString("Show notifications from people not in your contact list", comment: "notifications from unknown description");
        default:
            return nil;
        }
    }
        
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.section][indexPath.row];
        switch item {
        case .pushNotifications:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PushNotificationsTableViewCell", for: indexPath) as! SwitchTableViewCell;
            if anyAccountHasPush() && UIApplication.shared.isRegisteredForRemoteNotifications {
                cell.switchView.isEnabled = true;
                cell.bind({ c in
                    c.assign(from: Settings.$enablePush.map({ $0 ?? false}).eraseToAnyPublisher());
                    c.sink(map: { $0 as Bool? }, to: \.enablePush, on: Settings);
                })
            } else {
                cell.switchView.isOn = UIApplication.shared.isRegisteredForRemoteNotifications ? (Settings.enablePush ?? false) : false;
                cell.switchView.isEnabled = false;
            }
            return cell;
        case .notificationsFromUnknown:
            let cell = tableView.dequeueReusableCell(withIdentifier: "NotificationsFromUnknownTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.notificationsFromUnknown;
            cancellables.removeAll();
            cell.switchView.publisher(for: \.isOn).assign(to: \.notificationsFromUnknown, on: Settings).store(in: &cancellables);
            return cell;
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
    }
    
    private func anyAccountHasPush() -> Bool {
        return !AccountManager.getAccounts().filter({ AccountSettings.knownServerFeatures(for: $0).contains(.push) }).isEmpty;
    }
    
    internal enum SettingsEnum {
        case pushNotifications
        case notificationsFromUnknown
    }
    
}
