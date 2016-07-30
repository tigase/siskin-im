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
import TigaseSwift

class AddAccountController: UITableViewController {
    
    var account:String?;
    
    @IBOutlet var jidTextField: UITextField!
    
    @IBOutlet var passwordTextField: UITextField!
    
    @IBOutlet var saveButton: UIBarButtonItem!
    
    @IBOutlet var cancelButton: UIBarButtonItem!
    
    var activityInditcator: UIActivityIndicatorView?;
    
    var registerAccount: Bool = false;
    var xmppClient: XMPPClient?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        if account != nil {
            jidTextField.text = account;
            passwordTextField.text = AccountManager.getAccountPassword(account!);
            jidTextField.enabled = false;
        } else {
            navigationController?.navigationItem.leftBarButtonItem = nil;
        }

        if registerAccount {
            saveButton.title = "Register";
        } else {
            saveButton.title = "Save";
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        updateSaveButtonState();
        super.viewWillAppear(animated);
    }
    
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated);
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
        if (registerAccount) {
            registerAccountOnServer();
        } else {
            saveAccount();
        }
    }
    
    func registerAccountOnServer() {
        showIndicator();
        
        let userJid = BareJID(jidTextField.text!);
        let password = passwordTextField.text;
        
        xmppClient = InBandRegistrationModule.connectAndRegister(userJid: userJid, password: password, email: nil, onSuccess: {
            dispatch_async(dispatch_get_main_queue()) {
                self.hideIndicator();
                self.xmppClient = nil;
                self.saveAccount();
            }
            }, onError: { (errorCondition) in
                dispatch_async(dispatch_get_main_queue()) {
                    self.hideIndicator();
                    self.xmppClient = nil;
                    self.showError(errorCondition);
                }
        })
    }
    
    func saveAccount() {
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
    
    func showError(errorCondition: ErrorCondition?) {
        var error = "Operation timed out";
        if errorCondition != nil {
            switch errorCondition! {
            case .feature_not_implemented:
                error = "This sever do not allow registration of accounts";
            case .forbidden:
                error = "Registration of account if forbidden on this server";
            case .not_allowed:
                error = "Registration of account is not allowed";
            case .conflict:
                error = "Account already exists";
            default:
                error = "Unknown error occurred";
            }
        }
        let alert = UIAlertController(title: "Error", message:  error, preferredStyle: .Alert);
        alert.addAction(UIAlertAction(title: "Close", style: .Cancel, handler: nil));
        self.presentViewController(alert, animated: true, completion: nil);
    }
    
    func showIndicator() {
        if activityInditcator != nil {
            hideIndicator();
        }
        activityInditcator = UIActivityIndicatorView(activityIndicatorStyle: .Gray);
        activityInditcator?.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2);
        activityInditcator!.hidden = false;
        activityInditcator!.startAnimating();
        view.addSubview(activityInditcator!);
        view.bringSubviewToFront(activityInditcator!);
    }
    
    func hideIndicator() {
        activityInditcator?.stopAnimating();
        activityInditcator?.removeFromSuperview();
        activityInditcator = nil;
    }
}
