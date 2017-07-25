//
// SettingsViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

class SettingsViewController: UITableViewController, EventHandler {
   
    var statusNames = [
        "chat" : "Chat",
        "online" : "Online",
        "away" : "Away",
        "xa" : "Extended away",
        "dnd" : "Do not disturb"
    ];
    
    var xmppService:XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        xmppService.registerEventHandler(self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
        tableView.reloadData();
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Accounts";
        case 1:
            return "Status";
        case 2:
            return "Settings";
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return AccountManager.getAccounts().count + 1;
        case 1:
            return 2;
        case 2:
            return 3;
        default:
            return 0;
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section == 0) {
            let cellIdentifier = "AccountTableViewCell";
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! AccountTableViewCell;
            let accounts = AccountManager.getAccounts();
            if accounts.count > indexPath.row {
                cell.avatarStatusView.isHidden = false;
                let account = AccountManager.getAccount(forJid: accounts[indexPath.row]);
                cell.nameLabel.text = account?.name;
                let jid = BareJID(account!.name);
                cell.avatarStatusView.setAvatar(xmppService.avatarManager.getAvatar(for: jid, account: BareJID(account!.name)));
                if let client = xmppService.getClient(forJid: jid) {
                    cell.avatarStatusView.statusImageView.isHidden = false;
                    var status: Presence.Show? = nil;
                    switch client.state {
                    case .connected:
                        status = .online;
                    case .connecting, .disconnecting:
                        status = Presence.Show.xa;
                    default:
                        break;
                    }
                    cell.avatarStatusView.setStatus(status);
                } else {
                    cell.avatarStatusView.statusImageView.isHidden = true;
                }
                cell.avatarStatusView.updateCornerRadius();
            } else {
                cell.nameLabel.text = "Add account";
                cell.avatarStatusView.setAvatar(nil);
                cell.avatarStatusView.isHidden = true;
            }
            return cell;
        } else if (indexPath.section == 1) {
            if indexPath.row == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTableViewCell", for: indexPath);
                let label = cell.viewWithTag(1)! as! UILabel;
                label.text = Settings.StatusMessage.getString();
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTypeSettingsViewCell", for: indexPath);
                let type = Settings.StatusType.getString();
                if let image = type != nil ? getStatusIconForActionIcon(named: "presence_\(type!)") : nil {
                    (cell.contentView.subviews[0] as? UIImageView)?.image = image;
                    (cell.contentView.subviews[0] as? UIImageView)?.isHidden = false;
                } else {
                    (cell.contentView.subviews[0] as? UIImageView)?.isHidden = true;
                }
                (cell.contentView.subviews[1] as? UILabel)?.text = type != nil ? self.statusNames[type!] : "Automatic";
                cell.accessoryType = .disclosureIndicator;
                return cell;
            }
        } else {
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "ChatSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            } else if indexPath.row == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "ContactsSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "NotificationSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let accountCell = cell as? AccountTableViewCell {
            accountCell.avatarStatusView.updateCornerRadius();
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
        
        if indexPath.section == 0 {
            let accounts = AccountManager.getAccounts();
            if indexPath.row == accounts.count {
                let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
                alert.addAction(UIAlertAction(title: "Create new", style: .default, handler: { (action) in
                    self.showAddAccount(register: true);
                }));
                alert.addAction(UIAlertAction(title: "Add existing", style: .default, handler: { (action) in
                    self.showAddAccount(register: false);
                }));
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
                let cell = self.tableView(tableView, cellForRowAt: indexPath);
                alert.popoverPresentationController?.sourceView = cell.contentView;
                alert.popoverPresentationController?.sourceRect = cell.contentView.bounds;

                self.present(alert, animated: true, completion: nil);
            } else {
                // show edit account dialog
                let account = accounts[indexPath.row];
                let navigation = storyboard?.instantiateViewController(withIdentifier: "AccountSettingsNavigationController") as! UINavigationController;
                let accountSettingsController = navigation.visibleViewController! as! AccountSettingsViewController;
                accountSettingsController.hidesBottomBarWhenPushed = true;
                accountSettingsController.account = account;
                self.showDetailViewController(navigation, sender: self);
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                let alert = UIAlertController(title: "Select status", message: nil, preferredStyle: .actionSheet);
                [nil, "chat", "online", "away", "xa", "dnd"].forEach { (type)->Void in
                    let name = type == nil ? "Automatic" : self.statusNames[type!];
                    let action = UIAlertAction(title: name, style: .default) { (a) in
                        Settings.StatusType.setValue(type);
                        self.tableView.reloadData();                        
                    };
                    if type != nil {
                        action.setValue(getStatusIconForActionIcon(named: "presence_\(type!)"), forKey: "image")
                    }
                    alert.addAction(action);
                }
            
                let action = UIAlertAction(title: "Cancel", style: .cancel, handler: nil);
                alert.addAction(action);
                
                let cell = self.tableView(tableView, cellForRowAt: indexPath);
                alert.popoverPresentationController?.sourceView = cell.contentView;
                alert.popoverPresentationController?.sourceRect = cell.contentView.bounds;
                
                self.present(alert, animated: true, completion: nil);
            }
            else if indexPath.row == 1 {
                let alert = UIAlertController(title: "Status", message: "Enter status message", preferredStyle: .alert);
                alert.addTextField(configurationHandler: { (textField) in
                    textField.text = Settings.StatusMessage.getString();
                })
                alert.addAction(UIAlertAction(title: "Set", style: .default, handler: { (action) -> Void in
                    Settings.StatusMessage.setValue((alert.textFields![0] as UITextField).text);
                    self.tableView.reloadData();
                }));
                self.present(alert, animated: true, completion: nil);
            }
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if (indexPath.section == 0) {
            let accounts = AccountManager.getAccounts();
            return accounts.count > indexPath.row
        }
        return false;
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCellEditingStyle.delete {
            if indexPath.section == 0 {
                let accounts = AccountManager.getAccounts();
                if accounts.count > indexPath.row {
                    let account = accounts[indexPath.row];
                    let alert = UIAlertController(title: "Account removal", message: "Should account be removed from server as well?", preferredStyle: .actionSheet);
                    if let client = self.xmppService.getClient(forJid: BareJID(account)) {
                        alert.addAction(UIAlertAction(title: "Remove from server", style: .destructive, handler: { (action) in
                            let regModule = client.modulesManager.register(InBandRegistrationModule());
                            regModule.unregister({ (stanza) in
                                DispatchQueue.main.async() {
                                    AccountManager.deleteAccount(forJid: account);
                                    self.tableView.reloadData();
                                }
                            })
                        }));
                    }
                    alert.addAction(UIAlertAction(title: "Remove from application", style: .default, handler: { (action) in
                        AccountManager.deleteAccount(forJid: account);
                        self.tableView.reloadData();
                    }));
                    alert.addAction(UIAlertAction(title: "Keep account", style: .default, handler: nil));
                    let cell = self.tableView(tableView, cellForRowAt: indexPath);
                    alert.popoverPresentationController?.sourceView = cell.contentView;
                    alert.popoverPresentationController?.sourceRect = cell.contentView.bounds;

                    self.present(alert, animated: true, completion: nil);
                }
            }
        }
    }
    
    func handle(event: Event) {
        switch event {
        case is SocketConnector.ConnectedEvent, is SocketConnector.DisconnectedEvent, is StreamManagementModule.ResumedEvent,
             is SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            DispatchQueue.main.async() {
                self.tableView.reloadData();
            }
        default:
            break;
        }
    }
    
    func showAddAccount(register: Bool) {
        // show add account dialog
        let navigationController = storyboard!.instantiateViewController(withIdentifier: register ? "RegisterAccountController" : "AddAccountController") as! UINavigationController;
        if !register {
            let addAccountController = navigationController.visibleViewController! as! AddAccountController;
            addAccountController.hidesBottomBarWhenPushed = true;
        } else {
            let registerAccountController = navigationController.visibleViewController! as! RegisterAccountController;
            registerAccountController.hidesBottomBarWhenPushed = true;
        }
        self.showDetailViewController(navigationController, sender: self);
    }
    
    fileprivate func getStatusIconForActionIcon(named: String) -> UIImage? {
        guard var image = UIImage(named: named) else {
            return nil;
        }
        let newSize = CGSize(width: image.size.width * 0.5, height: image.size.height * 0.5);
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0);
        image.draw(in: CGRect(origin: CGPoint(x: 0, y: 0), size: newSize));
        image = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        return image.withRenderingMode(.alwaysOriginal);
    }
}
