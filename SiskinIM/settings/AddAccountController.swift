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
    
    var accountValidatorTask: Task<Void,Never>?;
    
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
        
        self.accountValidatorTask = Task {
            do {
                let acceptedCertificate = try await AccountValidatorTask.validate(controller: self, account: jid, password: password, connectivitySettings: connectivitySettings);
                await MainActor.run(body: {
                    guard !Task.isCancelled else {
                        return;
                    }
                    saveAccount(acceptedCertificate: acceptedCertificate);
                })
            } catch {
                await MainActor.run(body: {
                    self.hideIndicator();
                    self.saveButton.isEnabled = true;
                    var errorMessage = "";
                    switch (error as? XMPPError)?.condition ?? .undefined_condition {
                    case .not_authorized:
                        errorMessage = NSLocalizedString("Login and password do not match.", comment: "error message");
                    default:
                        errorMessage = NSLocalizedString("It was not possible to contact XMPP server and sign in.", comment: "error message");
                    }
                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: errorMessage, preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Close", comment: "button label"), style: .cancel, handler: nil));
                    self.present(alert, animated: true, completion: nil);
                })
            }
        }
    }
    
    func saveAccount(acceptedCertificate: SSLCertificateInfo?) {
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
        accountValidatorTask?.cancel();
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
    
    class AccountValidatorTask {
        
        public static func validate(controller: UIViewController, account: BareJID, password: String, connectivitySettings: AccountConnectivitySettingsViewController.Settings) async throws -> SSLCertificateInfo? {
            let client = XMPPClient();
            _ = client.modulesManager.register(StreamFeaturesModule());
            _ = client.modulesManager.register(SaslModule());
            _ = client.modulesManager.register(AuthModule());
            _ = client.modulesManager.register(ResourceBinderModule());
            _ = client.modulesManager.register(SessionEstablishmentModule());
            client.connectionConfiguration.useSeeOtherHost = false;
            client.connectionConfiguration.userJid = account;
            client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                if let host = connectivitySettings.host, let port = connectivitySettings.port {
                    options.connectionDetails = .init(proto: connectivitySettings.useDirectTLS ? .XMPPS : .XMPP, host: host, port: port)
                }
                options.networkProcessorProviders.append(connectivitySettings.disableTLS13 ? SSLProcessorProvider(supportedTlsVersions: TLSVersion.TLSv1_2...TLSVersion.TLSv1_2) : SSLProcessorProvider());
            })
            client.connectionConfiguration.credentials = .password(password: password, authenticationName: nil, cache: nil);
            defer {
                Task {
                    try await client.disconnect();
                }
            }
            do {
                try await client.loginAndWait();
                return nil;
            } catch let error as XMPPClient.State.DisconnectionReason {
                print(error)
                guard case let .sslCertError(trust) = error else {
                    throw error;
                }
                let certData = SSLCertificateInfo(trust: trust)!;
                guard await CertificateErrorAlert.show(parent: controller, domain: account.domain, certData: certData) else {
                    throw error;
                }
                client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                    options.networkProcessorProviders.append(SSLProcessorProvider());
                    options.sslCertificateValidation = .fingerprint(certData.subject.fingerprints.first!);
                });
                
                try await client.loginAndWait();
                return certData;
            }
        }
    }
}
