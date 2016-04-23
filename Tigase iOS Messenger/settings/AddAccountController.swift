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
    
    
    @IBOutlet var jidTextField: UITextField!
    
    @IBOutlet var passwordTextField: UITextField!
    
    @IBOutlet var signInButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(animated: Bool) {
        updateSignInButtonState();
        super.viewWillAppear(animated);
    }
    
    
    @IBAction func jidTextFieldChanged(sender: UITextField) {
        updateSignInButtonState();
    }
    
    @IBAction func passwordTextFieldChanged(sender: AnyObject) {
        updateSignInButtonState();
    }

    func updateSignInButtonState() {
        let disable = (jidTextField.text?.isEmpty ?? true) || (passwordTextField.text?.isEmpty ?? true);
        signInButton.enabled = !disable;
    }
    
    @IBAction func signInClicked(sender: UIBarButtonItem) {
        print("sign in button clicked");
        var account = AccountManager.Account(name: jidTextField.text!);
        AccountManager.updateAccount(account);
        account.password = passwordTextField.text!;
        self.navigationController?.popViewControllerAnimated(true);
    }
}
