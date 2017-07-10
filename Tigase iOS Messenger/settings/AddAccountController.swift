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

class AddAccountController: UITableViewController, UITextFieldDelegate {
    
    var account:String?;
    
    @IBOutlet var jidTextField: UITextField!
    
    @IBOutlet var passwordTextField: UITextField!
    
    @IBOutlet var cancelButton: UIBarButtonItem!;
    
    @IBOutlet var saveButton: UIBarButtonItem!
    
    var activityInditcator: UIActivityIndicatorView?;
    
    var xmppClient: XMPPClient?;
    
    var accountValidatorTask: AccountValidatorTask?;
    
    var onAccountAdded: (() -> Void)?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        if account != nil {
            jidTextField.text = account;
            passwordTextField.text = AccountManager.getAccountPassword(forJid: account!);
            jidTextField.isEnabled = false;
        } else {
            navigationController?.navigationItem.leftBarButtonItem = nil;
        }

        saveButton.title = "Save";
        jidTextField.delegate = self;
        passwordTextField.delegate = self;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        updateSaveButtonState();
        super.viewWillAppear(animated);
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        onAccountAdded = nil;
        super.viewWillDisappear(animated);
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
        //saveAccount();
        validateAccount();
    }
    
    func validateAccount() {
        self.saveButton.isEnabled = false;
        showIndicator();
        
        self.accountValidatorTask = AccountValidatorTask();
        self.accountValidatorTask?.check(account: BareJID(self.jidTextField.text)!, password: self.passwordTextField.text!, callback: self.handleResult);
    }
    
    func saveAccount() {
        print("sign in button clicked");
        let account = AccountManager.getAccount(forJid: jidTextField.text!) ?? AccountManager.Account(name: jidTextField.text!);
        AccountManager.updateAccount(account);
        account.password = passwordTextField.text!;

        onAccountAdded?();
        dismissView();
    }
    
    @IBAction func cancelClicked(_ sender: UIBarButtonItem) {
        dismissView();
    }
    
    func dismissView() {
        let dismiss = onAccountAdded != nil;
        onAccountAdded = nil;
        accountValidatorTask?.finish();
        accountValidatorTask = nil;
        
        if dismiss {
            navigationController?.dismiss(animated: true, completion: nil);
        } else {
            let newController = navigationController?.popViewController(animated: true);
            if newController == nil || newController != self {
                let emptyDetailController = storyboard!.instantiateViewController(withIdentifier: "emptyDetailViewController");
                self.showDetailViewController(emptyDetailController, sender: self);
            }
        }
        
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 0 && indexPath.row == 0 && !jidTextField.isEnabled {
            return nil;
        }
        return indexPath;
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == jidTextField {
            passwordTextField.becomeFirstResponder();
        } else {
            DispatchQueue.main.async {
                self.saveAccount();
            }
        }
        textField.resignFirstResponder();
        return false;
    }
    
    func handleResult(condition errorCondition: ErrorCondition?) {
        self.hideIndicator();
        self.accountValidatorTask = nil;
        if errorCondition != nil {
            self.saveButton.isEnabled = true;
            var error = "";
            switch errorCondition! {
            case .not_authorized:
                error = "Login and password do not match.";
            default:
                error = "It was not possible to contact XMPP server and sign in.";
            }
            let alert = UIAlertController(title: "Error", message:  error, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil));
            self.present(alert, animated: true, completion: nil);
        } else {
            self.saveAccount();
        }
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
    
    class AccountValidatorTask: EventHandler {
        
        var client: XMPPClient? {
            willSet {
                if newValue != nil {
                    newValue?.eventBus.register(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE);
                }
            }
            didSet {
                if oldValue != nil {
                    oldValue?.disconnect(true);
                    oldValue?.eventBus.unregister(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE);
                }
            }
        }
        
        var callback: ((ErrorCondition?)->Void)? = nil;
        
        init() {
            initClient();
        }
        
        fileprivate func initClient() {
            self.client = XMPPClient();
            _ = client?.modulesManager.register(StreamFeaturesModule());
            _ = client?.modulesManager.register(SaslModule());
            _ = client?.modulesManager.register(AuthModule());
        }
        
        public func check(account: BareJID, password: String, callback: @escaping (ErrorCondition?)->Void) {
            self.callback = callback;
            client?.connectionConfiguration.setUserJID(account);
            client?.connectionConfiguration.setUserPassword(password);
            client?.login();
        }
        
        public func handle(event: Event) {
            let callback = self.callback;
            finish();
            DispatchQueue.main.async {
                switch event {
                case is SaslModule.SaslAuthSuccessEvent:
                    callback?(nil);
                case is SaslModule.SaslAuthFailedEvent:
                    callback?(ErrorCondition.not_authorized);
                default:
                    callback?(ErrorCondition.service_unavailable);
                }
            }
        }
        
        public func finish() {
            self.callback = nil;
            self.client = nil;
        }
    }
}
