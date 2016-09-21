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
            jidTextField.isEnabled = false;
        } else {
            navigationController?.navigationItem.leftBarButtonItem = nil;
        }

        if registerAccount {
            saveButton.title = "Register";
        } else {
            saveButton.title = "Save";
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        updateSaveButtonState();
        super.viewWillAppear(animated);
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);
    }
    
    @IBAction func jidTextFieldChanged(_ sender: UITextField) {
        updateSaveButtonState();
    }
    
    @IBAction func passwordTextFieldChanged(_ sender: AnyObject) {
        updateSaveButtonState();
    }

    func updateSaveButtonState() {
        let disable = (jidTextField.text?.isEmpty ?? true) || (passwordTextField.text?.isEmpty ?? true);
        saveButton.isEnabled = !disable;
    }
    
    @IBAction func saveClicked(_ sender: UIBarButtonItem) {
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
            DispatchQueue.main.async() {
                self.hideIndicator();
                self.xmppClient = nil;
                self.saveAccount();
            }
            }, onError: { (errorCondition) in
                DispatchQueue.main.async() {
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
            navigationController?.dismiss(animated: true, completion: nil);
        } else {
            _ = navigationController?.popViewController(animated: true);
        }
    }
    
    @IBAction func cancelClicked(_ sender: UIBarButtonItem) {
        if self.account != nil {
            navigationController?.dismiss(animated: true, completion: nil);
        } else {
            _ = navigationController?.popViewController(animated: true);
        }
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 0 && indexPath.row == 0 && !jidTextField.isEnabled {
            return nil;
        }
        return indexPath;
    }
    
    func showError(_ errorCondition: ErrorCondition?) {
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
        let alert = UIAlertController(title: "Error", message:  error, preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil));
        self.present(alert, animated: true, completion: nil);
    }
    
    func showIndicator() {
        if activityInditcator != nil {
            hideIndicator();
        }
        activityInditcator = UIActivityIndicatorView(activityIndicatorStyle: .gray);
        activityInditcator?.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2);
        activityInditcator!.isHidden = false;
        activityInditcator!.startAnimating();
        view.addSubview(activityInditcator!);
        view.bringSubview(toFront: activityInditcator!);
    }
    
    func hideIndicator() {
        activityInditcator?.stopAnimating();
        activityInditcator?.removeFromSuperview();
        activityInditcator = nil;
    }
}
