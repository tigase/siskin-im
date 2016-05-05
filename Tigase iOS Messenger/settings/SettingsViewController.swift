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

class SettingsViewController: UITableViewController {
   
    var xmppService:XmppService {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        tableView.reloadData();
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Accounts";
        case 1:
            return "Other"
        default:
            return nil;
        }
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return AccountManager.getAccounts().count + 1;
        }
        return 1;
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cellIdentifier = "AccountTableViewCell";
        let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier, forIndexPath: indexPath) as! AccountTableViewCell;
        
        if (indexPath.section == 0) {
            let accounts = AccountManager.getAccounts();
            if accounts.count > indexPath.row {
                let account = AccountManager.getAccount(accounts[indexPath.row]);
                cell.nameLabel.text = account?.name;
                let jid = BareJID(account!.name);
                cell.avatarStatusView.setAvatar(xmppService.avatarManager.getAvatar(jid));
                cell.avatarStatusView.statusImageView.hidden = true;
            } else {
                cell.nameLabel.text = "Add account";
                cell.avatarStatusView.avatarImageView = nil;
                cell.avatarStatusView.hidden = true;
            }
        } else {
            cell.nameLabel.text = "Item s:\(indexPath.section),r:\(indexPath.row)";
        }
        
        return cell;
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true);
        
        if indexPath.section == 0 {
            let accounts = AccountManager.getAccounts();
            if indexPath.row == accounts.count {
                
                // show add account dialog
                let addAccountController = storyboard!.instantiateViewControllerWithIdentifier("AddAccountController") as! UINavigationController;
                addAccountController.visibleViewController!.hidesBottomBarWhenPushed = true;
                self.showDetailViewController(addAccountController, sender: self);
            } else {
                // show edit account dialog
                let account = accounts[indexPath.row];
                let navigation = storyboard?.instantiateViewControllerWithIdentifier("AccountSettingsNavigationController") as! UINavigationController;
                let accountSettingsController = navigation.childViewControllers[0] as! AccountSettingsViewController;
                accountSettingsController.account = account;
                self.showDetailViewController(navigation, sender: self);
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
                    AccountManager.deleteAccount(account);
                    tableView.reloadData();
                }
            }
        }
    }
}
