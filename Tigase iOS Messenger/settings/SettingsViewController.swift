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
            return "Other";
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return AccountManager.getAccounts().count + 1;
        case 1:
            return 1;
        case 2:
            return 5;
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
            } else {
                cell.nameLabel.text = "Add account";
                cell.avatarStatusView.setAvatar(nil);
                cell.avatarStatusView.isHidden = true;
            }
            return cell;
        } else if (indexPath.section == 1) {
            let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTableViewCell", for: indexPath);
            let label = cell.viewWithTag(1)! as! UILabel;
            label.text = Settings.StatusMessage.getString();
            return cell;
        } else {
            let setting = SettingsEnum(rawValue: indexPath.row)!;
            switch setting {
            case .deleteChatHistoryOnClose:
                let cell = tableView.dequeueReusableCell(withIdentifier: "DeleteChatHistoryOnCloseTableViewCell", for: indexPath) as! SwitchTableViewCell;
                cell.switchView.isOn = Settings.DeleteChatHistoryOnChatClose.getBool();
                cell.valueChangedListener = {(switchView: UISwitch) in
                    Settings.DeleteChatHistoryOnChatClose.setValue(switchView.isOn);
                }
                return cell;
            case .enableMessageCarbons:
                let cell = tableView.dequeueReusableCell(withIdentifier: "EnableMessageCarbonsTableViewCell", for: indexPath ) as! SwitchTableViewCell;
                cell.switchView.isOn = Settings.EnableMessageCarbons.getBool();
                cell.valueChangedListener = {(switchView: UISwitch) in
                    Settings.EnableMessageCarbons.setValue(switchView.isOn);
                }
                return cell;
            case .rosterType:
                let cell = tableView.dequeueReusableCell(withIdentifier: "RosterTypeTableViewCell", for: indexPath ) as! SwitchTableViewCell;
                cell.switchView.isOn = Settings.RosterType.getString() == RosterType.grouped.rawValue;
                cell.valueChangedListener = {(switchView: UISwitch) in
                    Settings.RosterType.setValue((switchView.isOn ? RosterType.grouped : RosterType.flat).rawValue);
                }
                return cell;
            case .rosterDisplayHiddenGroup:
                let cell = tableView.dequeueReusableCell(withIdentifier: "RosterHiddenGroupTableViewCell", for: indexPath) as! SwitchTableViewCell;
                cell.switchView.isOn = Settings.RosterDisplayHiddenGroup.getBool();
                cell.valueChangedListener = {(switchView: UISwitch) in
                    Settings.RosterDisplayHiddenGroup.setValue(switchView.isOn);
                }
                return cell;
            case .autoSubscribeOnAcceptedSubscriptionRequest:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AutoSubscribeOnAcceptedSubscriptionRequestTableViewCell", for: indexPath) as! SwitchTableViewCell;
                cell.switchView.isOn = Settings.AutoSubscribeOnAcceptedSubscriptionRequest.getBool();
                cell.valueChangedListener = {(switchView: UISwitch) in
                    Settings.AutoSubscribeOnAcceptedSubscriptionRequest.setValue(switchView.isOn);
                }
                return cell;
            }
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
        let navigationController = storyboard!.instantiateViewController(withIdentifier: "AddAccountController") as! UINavigationController;
        let addAccountController = navigationController.visibleViewController! as! AddAccountController;
        addAccountController.hidesBottomBarWhenPushed = true;
        addAccountController.registerAccount = register;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    internal enum SettingsEnum: Int {
        case deleteChatHistoryOnClose = 0
        case enableMessageCarbons = 1
        case rosterType = 2
        case rosterDisplayHiddenGroup = 3
        case autoSubscribeOnAcceptedSubscriptionRequest = 4
    }
}
