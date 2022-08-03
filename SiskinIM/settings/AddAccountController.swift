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
import Martin
import Combine
import Shared

class AddAccountController: UITableViewController, UITextFieldDelegate {
    
    var account:String?;
    
    @IBOutlet var jidTextField: UITextField!
    
    @IBOutlet var passwordTextField: UITextField!
    
    @IBOutlet var cancelButton: UIBarButtonItem!;
    
    @IBOutlet var saveButton: UIBarButtonItem!
    
    var activityInditcator: UIActivityIndicatorView?;
    
    var xmppClient: XMPPClient?;
    
    var accountValidatorTask: AccountValidatorTask?;
    
    var connectivitySettings = AccountConnectivitySettingsViewController.Settings();
    
//    var onAccountAdded: (() -> Void)?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        if account != nil {
            jidTextField.text = account;
            passwordTextField.text = AccountManager.getAccountPassword(for: BareJID(account)!);
            jidTextField.isEnabled = false;
            if let acc = AccountManager.getAccount(for: BareJID(account)!) {
                connectivitySettings.disableTLS13 = acc.disableTLS13;
                if let endpoint = acc.endpoint {
                    connectivitySettings.host = endpoint.host;
                    connectivitySettings.port = endpoint.port;
                    connectivitySettings.useDirectTLS = endpoint.proto == .XMPPS;
                }
            }
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let advSettingsController = segue.destination as? AccountConnectivitySettingsViewController {
            advSettingsController.values = connectivitySettings;
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
//        onAccountAdded = nil;
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
        guard let jid = BareJID(self.jidTextField.text), let password = self.passwordTextField.text, !password.isEmpty else {
            return;
        }
        
        self.saveButton.isEnabled = false;
        showIndicator();
        
        self.accountValidatorTask = AccountValidatorTask(controller: self);
        self.accountValidatorTask?.check(account: jid, password: password, connectivitySettings: connectivitySettings, callback: self.handleResult);
    }
    
    func saveAccount(acceptedCertificate: SslCertificateInfo?) {
        guard let jid = BareJID(jidTextField.text) else {
            return;
        }
        var account = AccountManager.getAccount(for: jid) ?? AccountManager.Account(name: jid);
        account.acceptCertificate(acceptedCertificate);
        account.password = passwordTextField.text!;
        if let host = connectivitySettings.host, let port = connectivitySettings.port {
            account.endpoint = .init(proto: connectivitySettings.useDirectTLS ? .XMPPS : .XMPP, host: host, port: port)
        }
        account.disableTLS13 = connectivitySettings.disableTLS13;

        var cancellables: Set<AnyCancellable> = [];
        do {
            try AccountManager.save(account: account);
            self.dismissView();
            (UIApplication.shared.delegate as? AppDelegate)?.showSetup(value: false);
        } catch {
            self.hideIndicator();
            cancellables.removeAll();
            let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to save account details: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    @IBAction func cancelClicked(_ sender: UIBarButtonItem) {
        dismissView();
    }
    
    func dismissView() {
        let dismiss = self.view.window?.rootViewController is SetupViewController;
//        onAccountAdded = nil;
        accountValidatorTask?.finish();
        accountValidatorTask = nil;
        
        if dismiss {
            navigationController?.dismiss(animated: true, completion: nil);
        } else {
            let newController = navigationController?.popViewController(animated: true);
            if newController == nil || newController != self {
                let emptyDetailController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "emptyDetailViewController");
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
    
    func handleResult(result: Result<Void,ErrorCondition>) {
        let acceptedCertificate = accountValidatorTask?.acceptedCertificate;
        self.accountValidatorTask = nil;
        switch result {
        case .failure(let errorCondition):
            self.hideIndicator();
            self.saveButton.isEnabled = true;
            var error = "";
            switch errorCondition {
            case .not_authorized:
                error = NSLocalizedString("Login and password do not match.", comment: "error message");
            default:
                error = NSLocalizedString("It was not possible to contact XMPP server and sign in.", comment: "error message");
            }
            let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message:  error, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Close", comment: "button label"), style: .cancel, handler: nil));
            self.present(alert, animated: true, completion: nil);
        case .success(_):
            self.saveAccount(acceptedCertificate: acceptedCertificate);
        }
    }
    
    func showIndicator() {
        if activityInditcator != nil {
            hideIndicator();
        }
        activityInditcator = UIActivityIndicatorView(style: .medium);
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
        
        private var cancellables: Set<AnyCancellable> = [];
        var client: XMPPClient? {
            willSet {
                if newValue != nil {
                    newValue?.eventBus.register(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
                }
            }
            didSet {
                cancellables.removeAll();
                if oldValue != nil {
                    _ = oldValue?.disconnect(true);
                    oldValue?.eventBus.unregister(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
                }
                client?.$state.sink(receiveValue: { [weak self] state in self?.changedState(state) }).store(in: &cancellables);
            }
        }
        
        var callback: ((Result<Void,ErrorCondition>)->Void)? = nil;
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
        }
        
        public func check(account: BareJID, password: String, connectivitySettings: AccountConnectivitySettingsViewController.Settings, callback: @escaping (Result<Void,ErrorCondition>)->Void) {
            self.callback = callback;
            client?.connectionConfiguration.useSeeOtherHost = false;
            client?.connectionConfiguration.userJid = account;
            client?.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                if let host = connectivitySettings.host, let port = connectivitySettings.port {
                    options.connectionDetails = .init(proto: connectivitySettings.useDirectTLS ? .XMPPS : .XMPP, host: host, port: port)
                }
                options.networkProcessorProviders.append(connectivitySettings.disableTLS13 ? SSLProcessorProvider(supportedTlsVersions: TLSVersion.TLSv1_2...TLSVersion.TLSv1_2) : SSLProcessorProvider());
            })
            client?.connectionConfiguration.credentials = .password(password: password, authenticationName: nil, cache: nil);
            client?.login();
        }
        
        public func handle(event: Event) {
            dispatchQueue.sync {
                guard let callback = self.callback else {
                    return;
                }
                var param: ErrorCondition? = nil;
                switch event {
                case is SaslModule.SaslAuthSuccessEvent:
                    param = nil;
                case is SaslModule.SaslAuthFailedEvent:
                    param = ErrorCondition.not_authorized;
                default:
                    param = ErrorCondition.service_unavailable;
                }
                
                DispatchQueue.main.async {
                    if let error = param {
                        callback(.failure(error));
                    } else {
                        callback(.success(Void()));
                    }
                }
                self.finish();
            }
        }
        
        func changedState(_ state: XMPPClient.State) {
            dispatchQueue.sync {
                guard let callback = self.callback else {
                    return;
                }
                
                switch state {
                case .disconnected(let reason):
                    switch reason {
                    case .sslCertError(let trust):
                        self.callback = nil;
                        let certData = SslCertificateInfo(trust: trust);
                        let alert = CertificateErrorAlert.create(domain: self.client!.sessionObject.userBareJid!.domain, certData: certData, onAccept: {
                            self.acceptedCertificate = certData;
                            self.client?.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                                options.networkProcessorProviders.append(SSLProcessorProvider());
                                options.sslCertificateValidation = .fingerprint(certData.details.fingerprintSha1);
                            });
                            self.callback = callback;
                            self.client?.login();
                        }, onDeny: {
                            self.finish();
                            callback(.failure(ErrorCondition.service_unavailable));
                        })
                        DispatchQueue.main.async {
                            self.controller?.present(alert, animated: true, completion: nil);
                        }
                        return;
                    default:
                        break;
                    }
                    DispatchQueue.main.async {
                        callback(.failure(.service_unavailable));
                    }
                    self.finish();
                default:
                    break;
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
