//
// AddAccountController.swift
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

class AddAccountController: UITableViewController {
    
    var account:String?;
    
    @IBOutlet var jidTextField: UITextField!
    
    @IBOutlet var passwordTextField: UITextField!
    
    @IBOutlet var saveButton: UIBarButtonItem!
    
    @IBOutlet var cancelButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad();
        if account != nil {
            jidTextField.text = account;
            passwordTextField.text = AccountManager.getAccountPassword(account!);
            jidTextField.enabled = false;
        } else {
            navigationController?.navigationItem.leftBarButtonItem = nil;
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        updateSaveButtonState();
        super.viewWillAppear(animated);
    }
    
    
    @IBAction func jidTextFieldChanged(sender: UITextField) {
        updateSaveButtonState();
    }
    
    @IBAction func passwordTextFieldChanged(sender: AnyObject) {
        updateSaveButtonState();
    }

    func updateSaveButtonState() {
        let disable = (jidTextField.text?.isEmpty ?? true) || (passwordTextField.text?.isEmpty ?? true);
        saveButton.enabled = !disable;
    }
    
    @IBAction func saveClicked(sender: UIBarButtonItem) {
        print("sign in button clicked");
        let account = AccountManager.getAccount(jidTextField.text!) ?? AccountManager.Account(name: jidTextField.text!);
        AccountManager.updateAccount(account);
        account.password = passwordTextField.text!;

        if self.account != nil {
            navigationController?.dismissViewControllerAnimated(true, completion: nil);
        } else {
            navigationController?.popViewControllerAnimated(true);
        }
    }
    
    @IBAction func cancelClicked(sender: UIBarButtonItem) {
        if self.account != nil {
            navigationController?.dismissViewControllerAnimated(true, completion: nil);
        } else {
            navigationController?.popViewControllerAnimated(true);
        }
    }
    
    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        if indexPath.section == 0 && indexPath.row == 0 && !jidTextField.enabled {
            return nil;
        }
        return indexPath;
    }
}
