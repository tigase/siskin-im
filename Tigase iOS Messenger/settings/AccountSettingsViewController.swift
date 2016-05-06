//
// AccountSettingsViewController.swift
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

class AccountSettingsViewController: UITableViewController {
    
    var account:String!;
        
    @IBOutlet var enabledSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        let config = AccountManager.getAccount(account);
        enabledSwitch.on = config?.active ?? false;
    }
    
    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        if indexPath.row == 0 {
            return nil;
        }
        return indexPath;
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "EditAccountSegue" {
            let navigation = segue.destinationViewController as! UINavigationController;
            let destination = navigation.visibleViewController as! AddAccountController;
            destination.account = account;
        }
    }
    
    @IBAction func enabledSwitchChangedValue(sender: AnyObject) {
        if let config = AccountManager.getAccount(account) {
            config.active = enabledSwitch.on;
            AccountManager.updateAccount(config);
        }
    }
}
