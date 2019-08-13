//
// MucChatSettingsViewController.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class MucChatSettingsViewController: CustomTableViewController {
    
    @IBOutlet var roomNameField: UILabel!;
    @IBOutlet var pushNotificationsSwitch: UISwitch!;
    @IBOutlet var notificationsField: UILabel!;
    
    fileprivate var activityIndicator: UIActivityIndicatorView?;
    
    var account: BareJID!;
    var room: DBRoom!;
    
    override func viewWillAppear(_ animated: Bool) {
        view.backgroundColor = Appearance.current.tableViewBackgroundColor();
        roomNameField.text = room.roomName ?? "";
        pushNotificationsSwitch.isEnabled = false;
        pushNotificationsSwitch.isOn = false;
        
        refresh();
    }
    
    @objc func dismissView() {
        self.dismiss(animated: true, completion: nil);
    }
    
    func refresh() {
        notificationsField.text = NotificationItem(type: room.options.notifications).description;
        
        guard let client = XmppService.instance.getClient(forJid: account), let discoveryModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        showIndicator();
        discoveryModule.getInfo(for: room.jid, onInfoReceived: { (node, identities, features) in
            DispatchQueue.main.async {
                let pushModule: TigasePushNotificationsModule? = client.modulesManager.getModule(TigasePushNotificationsModule.ID);
                self.pushNotificationsSwitch.isEnabled = (pushModule?.enabled ?? false) && features.contains("jabber:iq:register");
                if self.pushNotificationsSwitch.isEnabled {
                    self.room.checkTigasePushNotificationRegistrationStatus(completionHandler: { (result) in
                        switch result {
                        case .failure(_):
                            DispatchQueue.main.async {
                                self.pushNotificationsSwitch.isEnabled = false;
                                self.hideIndicator();
                            }
                        case .success(let value):
                            DispatchQueue.main.async {
                                self.pushNotificationsSwitch.isOn = value;
                                self.hideIndicator();
                            }
                        }
                    })
                } else {
                    self.hideIndicator();
                }
            }
        }, onError: { error in
            DispatchQueue.main.async {
                self.pushNotificationsSwitch.isEnabled = false;
                self.hideIndicator();
            }
        })
    }
    
    @IBAction func pushNotificationSwitchChanged(_ sender: UISwitch) {
        self.room.registerForTigasePushNotification(sender.isOn) { (result) in
            switch result {
            case .failure(_):
                DispatchQueue.main.async {
                    sender.isOn = !sender.isOn;
                }
            case .success(_):
                // nothing to do..
                break;
            }
        }
    }
    
    func showIndicator() {
        if activityIndicator != nil {
            hideIndicator();
        }
        activityIndicator = UIActivityIndicatorView(style: .gray);
        activityIndicator?.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2);
        activityIndicator!.isHidden = false;
        activityIndicator!.startAnimating();
        view.addSubview(activityIndicator!);
        view.bringSubviewToFront(activityIndicator!);
    }
    
    func hideIndicator() {
        activityIndicator?.stopAnimating();
        activityIndicator?.removeFromSuperview();
        activityIndicator = nil;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        if indexPath.section == 0 && indexPath.row == 1 {
            let controller = TablePickerViewController();
            controller.items = [NotificationItem(type: .always), NotificationItem(type: .mention), NotificationItem(type: .none)];
            controller.selected = controller.items.firstIndex(where: { (item) -> Bool in
                return (item as! NotificationItem).type == room.options.notifications;
            })!;
            controller.onSelectionChange = { item in
                self.notificationsField.text = item.description;
                
                self.room.modifyOptions({ (options) in
                    options.notifications = (item as! NotificationItem).type;
                })
            }
            self.navigationController?.pushViewController(controller, animated: true);
        }
    }
    
    class NotificationItem: TablePickerViewItemsProtocol {
        
        let type: RoomNotifications;
        
        var description: String {
            get {
                switch type {
                case .none:
                    return "Muted";
                case .mention:
                    return "When mentioned";
                case .always:
                    return "Always";
                }
            }
        }
        
        init(type: RoomNotifications) {
            self.type = type;
        }
        
    }
}
