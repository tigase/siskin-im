//
// AddAccountController.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//


import UIKit
import TigaseSwift

class AddAccountController: CustomTableViewController, UITextFieldDelegate {
    
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

        jidTextField.keyboardType = .emailAddress;
        if #available(iOS 11.0, *) {
            jidTextField.textContentType = .username;
            passwordTextField.textContentType = .password;
        };
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
        
        self.accountValidatorTask = AccountValidatorTask(controller: self);
        self.accountValidatorTask?.check(account: BareJID(self.jidTextField.text)!, password: self.passwordTextField.text!, callback: self.handleResult);
    }
    
    func saveAccount(acceptedCertificate: SslCertificateInfo?) {
        print("sign in button clicked");
        let account = AccountManager.getAccount(forJid: jidTextField.text!) ?? AccountManager.Account(name: jidTextField.text!);
        account.acceptCertificate(acceptedCertificate);
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
                self.validateAccount();
            }
        }
        textField.resignFirstResponder();
        return false;
    }
    
    func handleResult(condition errorCondition: ErrorCondition?) {
        self.hideIndicator();
        let acceptedCertificate = accountValidatorTask?.acceptedCertificate;
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
            self.saveAccount(acceptedCertificate: acceptedCertificate);
        }
    }
    
    func showIndicator() {
        if activityInditcator != nil {
            hideIndicator();
        }
        activityInditcator = UIActivityIndicatorView(style: .gray);
        activityInditcator?.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2);
        activityInditcator!.isHidden = false;
        activityInditcator!.startAnimating();
        view.addSubview(activityInditcator!);
        view.bringSubviewToFront(activityInditcator!);
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
                    newValue?.eventBus.register(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE);
                }
            }
            didSet {
                if oldValue != nil {
                    oldValue?.disconnect(true);
                    oldValue?.eventBus.unregister(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE);
                }
            }
        }
        
        var callback: ((ErrorCondition?)->Void)? = nil;
        weak var controller: UIViewController?;
        var dispatchQueue = DispatchQueue(label: "accountValidatorSync");
        
        var acceptedCertificate: SslCertificateInfo? = nil;
        
        init(controller: UIViewController) {
            self.controller = controller;
            initClient();
        }
        
        fileprivate func initClient() {
            self.client = XMPPClient();
            _ = client?.modulesManager.register(StreamFeaturesModule());
            _ = client?.modulesManager.register(SaslModule());
            _ = client?.modulesManager.register(AuthModule());
            SslCertificateValidator.registerSslCertificateValidator(client!.sessionObject);
        }
        
        public func check(account: BareJID, password: String, callback: @escaping (ErrorCondition?)->Void) {
            self.callback = callback;
            client?.connectionConfiguration.setUserJID(account);
            client?.connectionConfiguration.setUserPassword(password);
            client?.login();
        }
        
        public func handle(event: Event) {
            dispatchQueue.sync {
                let callback = self.callback;
                var param: ErrorCondition? = nil;
                switch event {
                case is SaslModule.SaslAuthSuccessEvent:
                    param = nil;
                case is SaslModule.SaslAuthFailedEvent:
                    param = ErrorCondition.not_authorized;
                case let e as SocketConnector.CertificateErrorEvent:
                    self.callback = nil;
                    let certData = SslCertificateInfo(trust: e.trust);
                    let alert = CertificateErrorAlert.create(domain: self.client!.sessionObject.userBareJid!.domain, certData: certData, onAccept: {
                        self.acceptedCertificate = certData;
                        SslCertificateValidator.setAcceptedSslCertificate(self.client!.sessionObject, fingerprint: certData.details.fingerprintSha1);
                        self.callback = callback;
                        self.client?.login();
                    }, onDeny: {
                        self.finish();
                        callback?(ErrorCondition.service_unavailable);
                    })
                    DispatchQueue.main.async {
                        self.controller?.present(alert, animated: true, completion: nil);
                    }
                    return;
                default:
                    param = ErrorCondition.service_unavailable;
                }
                
                if (callback != nil) {
                    self.finish();
                    DispatchQueue.main.async {
                        callback?(param);
                    }
                }
            }
        }
        
        public func finish() {
            self.callback = nil;
            self.client = nil;
            self.controller = nil;
        }
    }
}
