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
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        xmppService.registerEventHandler(self, events: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
        tableView.reloadData();
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, events: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 3;
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
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
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return AccountManager.getAccounts().count + 1;
        case 1:
            return 1;
        case 2:
            return 2;
        default:
            return 0;
        }
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if (indexPath.section == 0) {
            let cellIdentifier = "AccountTableViewCell";
            let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier, forIndexPath: indexPath) as! AccountTableViewCell;
            let accounts = AccountManager.getAccounts();
            if accounts.count > indexPath.row {
                let account = AccountManager.getAccount(accounts[indexPath.row]);
                cell.nameLabel.text = account?.name;
                let jid = BareJID(account!.name);
                cell.avatarStatusView.setAvatar(xmppService.avatarManager.getAvatar(jid, account: BareJID(account!.name)));
                if let client = xmppService.getClient(jid) {
                    cell.avatarStatusView.statusImageView.hidden = false;
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
                    cell.avatarStatusView.statusImageView.hidden = true;
                }
            } else {
                cell.nameLabel.text = "Add account";
                cell.avatarStatusView.setAvatar(nil);
                cell.avatarStatusView.hidden = true;
            }
            return cell;
        } else if (indexPath.section == 1) {
            let cell = tableView.dequeueReusableCellWithIdentifier("StatusTableViewCell", forIndexPath: indexPath);
            let label = cell.viewWithTag(1)! as! UILabel;
            label.text = Settings.StatusMessage.getString();
            return cell;
        } else {
            let setting = SettingsEnum(rawValue: indexPath.row)!;
            switch setting {
            case .DeleteChatHistoryOnClose:
                let cell = tableView.dequeueReusableCellWithIdentifier("DeleteChatHistoryOnCloseTableViewCell", forIndexPath: indexPath) as! SwitchTableViewCell;
                cell.switchView.on = Settings.DeleteChatHistoryOnChatClose.getBool();
                cell.valueChangedListener = {(switchView) in
                    Settings.DeleteChatHistoryOnChatClose.setValue(switchView.on);
                }
                return cell;
            case .EnableMessageCarbons:
                let cell = tableView.dequeueReusableCellWithIdentifier("EnableMessageCarbonsTableViewCell", forIndexPath: indexPath) as! SwitchTableViewCell;
                cell.switchView.on = Settings.EnableMessageCarbons.getBool();
                cell.valueChangedListener = {(switchView) in
                    Settings.EnableMessageCarbons.setValue(switchView.on);
                }
                return cell;
            }
            
        }
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true);
        
        if indexPath.section == 0 {
            let accounts = AccountManager.getAccounts();
            if indexPath.row == accounts.count {
                let alert = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet);
                alert.addAction(UIAlertAction(title: "Create new", style: .Default, handler: { (action) in
                    self.showAddAccount(true);
                }));
                alert.addAction(UIAlertAction(title: "Add existing", style: .Default, handler: { (action) in
                    self.showAddAccount(false);
                }));
                alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil));
                
                self.presentViewController(alert, animated: true, completion: nil);
            } else {
                // show edit account dialog
                let account = accounts[indexPath.row];
                let navigation = storyboard?.instantiateViewControllerWithIdentifier("AccountSettingsNavigationController") as! UINavigationController;
                let accountSettingsController = navigation.visibleViewController! as! AccountSettingsViewController;
                accountSettingsController.hidesBottomBarWhenPushed = true;
                accountSettingsController.account = account;
                self.showDetailViewController(navigation, sender: self);
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                let alert = UIAlertController(title: "Status", message: "Enter status message", preferredStyle: .Alert);
                alert.addTextFieldWithConfigurationHandler({ (textField) in
                    textField.text = Settings.StatusMessage.getString();
                })
                alert.addAction(UIAlertAction(title: "Set", style: .Default, handler: { (action) -> Void in
                    Settings.StatusMessage.setValue((alert.textFields![0] as UITextField).text);
                    self.tableView.reloadData();
                }));
                self.presentViewController(alert, animated: true, completion: nil);
            }
        }
    }

    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        if (indexPath.section == 0) {
            let accounts = AccountManager.getAccounts();
            return accounts.count > indexPath.row
        }
        return false;
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == UITableViewCellEditingStyle.Delete {
            if indexPath.section == 0 {
                let accounts = AccountManager.getAccounts();
                if accounts.count > indexPath.row {
                    let account = accounts[indexPath.row];
                    let alert = UIAlertController(title: "Account removal", message: "Should account be removed from server as well?", preferredStyle: .ActionSheet);
                    if let client = self.xmppService.getClient(BareJID(account)) {
                        alert.addAction(UIAlertAction(title: "Remove", style: .Destructive, handler: { (action) in
                            let regModule = client.modulesManager.register(InBandRegistrationModule());
                            regModule.unregister({ (stanza) in
                                dispatch_async(dispatch_get_main_queue()) {
                                    AccountManager.deleteAccount(account);
                                    self.tableView.reloadData();
                                }
                            })
                        }));
                    }
                    alert.addAction(UIAlertAction(title: "Keep", style: .Default, handler: { (action) in
                        AccountManager.deleteAccount(account);
                        self.tableView.reloadData();
                    }));
                    alert.addAction(UIAlertAction(title: "Cancel", style: .Default, handler: nil));
                    self.presentViewController(alert, animated: true, completion: nil);
                }
            }
        }
    }
    
    func handleEvent(event: Event) {
        switch event {
        case is SocketConnector.ConnectedEvent, is SocketConnector.DisconnectedEvent, is StreamManagementModule.ResumedEvent,
             is SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            dispatch_async(dispatch_get_main_queue()) {
                self.tableView.reloadData();
            }
        default:
            break;
        }
    }
    
    func showAddAccount(register: Bool) {
        // show add account dialog
        let navigationController = storyboard!.instantiateViewControllerWithIdentifier("AddAccountController") as! UINavigationController;
        let addAccountController = navigationController.visibleViewController! as! AddAccountController;
        addAccountController.hidesBottomBarWhenPushed = true;
        addAccountController.registerAccount = register;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    internal enum SettingsEnum: Int {
        case DeleteChatHistoryOnClose = 0
        case EnableMessageCarbons = 1
    }
}
