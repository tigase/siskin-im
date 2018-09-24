//
// RegisterAccountController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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
import Foundation

import UIKit
import TigaseSwift

class RegisterAccountController: DataFormController, UITextFieldDelegate {

    @IBOutlet var nextButton: UIBarButtonItem!
    
    var domain: String? = nil;
    
    var domainFieldValue: String? = nil;

    let trustedServers = [ "tigase.im", "sure.im", "jabber.today" ];
    
    var task: InBandRegistrationModule.AccountRegistrationTask?;
    
    var activityIndicator: UIActivityIndicatorView!;
    
    var onAccountAdded: (() -> Void)?;
    
    var account: BareJID? = nil;
    var password: String? = nil;
    
    override func viewWillDisappear(_ animated: Bool) {
        onAccountAdded = nil;
        super.viewWillDisappear(animated);
    }
    
    func updateDomain(_ newValue: String?) {
        if newValue != nil && !newValue!.isEmpty && domain != newValue {
            nextButton.isEnabled = false;
            nextButton.title = "Register";
            let count = self.numberOfSections(in: tableView);
            self.domain = newValue;
            tableView.deleteSections(IndexSet(0..<count), with: .fade);
            showIndicator();
            self.retrieveRegistrationForm(domain: newValue!);
        }
    }
    

    @IBAction func nextButtonClicked(_ sender: Any) {
        guard domain != nil else {
            DispatchQueue.main.async {
                self.updateDomain(self.domainFieldValue);
            }
            return;
        }
        guard form != nil && validateForm() else {
            return;
        }
        
        let jid = BareJID((form?.getField(named: "username") as? TextSingleField)?.value);
        self.account = BareJID(localPart: jid?.localPart ?? jid?.domain, domain: domain!);
        self.password = (form?.getField(named: "password") as? TextPrivateField)?.value;
        task?.submit(form: form!);
        self.showIndicator();
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        guard domain != nil else {
            return 2;
        }
        return super.numberOfSections(in: tableView);
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard domain != nil else {
            switch section {
            case 0:
                return 1;
            default:
                return trustedServers.count;
            }
        }
        return super.tableView(tableView, numberOfRowsInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard domain != nil else {
            switch section {
            case 0:
                return "Preferred domain name";
            case 1:
                return "Trusted servers";
            default:
                return "";
            }
        }
        
        return super.tableView(tableView, titleForHeaderInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard domain != nil else {
            switch indexPath.section {
            case 0:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AccountDomainTableViewCell", for: indexPath) as! AccountDomainTableViewCell;
                cell.domainField.addTarget(self, action: #selector(domainFieldChanged(domainField:)), for: .editingChanged);
                return cell;
            default:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ServerSelectorTableViewCell", for: indexPath) as! ServerSelectorTableViewCell;
                cell.serverDomain.text = trustedServers[indexPath.row];
                return cell;
            }
        }
        
        return super.tableView(tableView, cellForRowAt: indexPath);
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard domain != nil else {
            switch section {
            case 0:
                return "If you don't know any XMPP server domain names, then select one of our trusted servers."
            default:
                return nil;
            }
        }
        return nil;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard domain != nil else {
            tableView.deselectRow(at: indexPath, animated: false);
            if indexPath.section == 1 {
                DispatchQueue.main.async {
                    self.updateDomain(self.trustedServers[indexPath.row]);
                }
            }
            return;
        }
        
        super.tableView(tableView, didSelectRowAt: indexPath);
    }
    
    func saveAccount(acceptedCertificate: SslCertificateInfo?) {
        let account = AccountManager.getAccount(forJid: self.account!.stringValue) ?? AccountManager.Account(name: self.account!.stringValue);
        account.acceptCertificate(acceptedCertificate);
        AccountManager.updateAccount(account);
        account.password = self.password!;
        
        onAccountAdded?();
    }
    
    func retrieveRegistrationForm(domain: String) {
        let onForm = {(form: JabberDataElement, task: InBandRegistrationModule.AccountRegistrationTask)->Void in
            DispatchQueue.main.async {
                self.nextButton.isEnabled = true;
                self.hideIndicator();
                self.form = form;
                self.tableView.insertSections(IndexSet(0..<1), with: .fade);
            }
        };
        let onSuccess = {()->Void in
            print("account registered!");
            let certData: SslCertificateInfo? = self.task?.getAcceptedCertificate();
            DispatchQueue.main.async {
                self.saveAccount(acceptedCertificate: certData);
                self.dismissView();
            }
        };
        let client: XMPPClient? = nil;
        self.task = InBandRegistrationModule.AccountRegistrationTask(client: client, domainName: domain, onForm: onForm, onSuccess: onSuccess, onError: self.onRegistrationError, sslCertificateValidator: SslCertificateValidator.validateSslCertificate, onCertificateValidationError: self.onCertificateError);
    }
    
    func onRegistrationError(errorCondition: ErrorCondition?, message: String?) {
        DispatchQueue.main.async {
            self.nextButton.isEnabled = true;
            self.hideIndicator();
        }
        print("account registration failed", errorCondition?.rawValue ?? "nil", "with message =", message as Any);
        var msg = message;
        
        if errorCondition == nil {
            msg = "Server did not respond on registration request";
        } else {
            if msg == nil || msg == "Unsuccessful registration attempt" {
                switch errorCondition! {
                case .feature_not_implemented:
                    msg = "Registration is not supported by this server";
                case .not_acceptable, .not_allowed:
                    msg = "Provided values are not acceptable";
                case .conflict:
                    msg = "User with provided username already exists";
                case .service_unavailable:
                    msg = "Service is not available at this time."
                default:
                    msg = "Server returned error: \(errorCondition!.rawValue)";
                }
            }
        }
        var handler: ((UIAlertAction?)->Void)? = nil;
        
        if errorCondition == ErrorCondition.feature_not_implemented || errorCondition == ErrorCondition.service_unavailable {
            handler = {(action)->Void in
                self.dismissView();
            };
        }
        
        let alert = UIAlertController(title: "Registration failure", message: msg, preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: handler));
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    func onCertificateError(certData: SslCertificateInfo, accepted: @escaping ()->Void) {
        let alert = CertificateErrorAlert.create(domain: domain!, certData: certData, onAccept: accepted, onDeny: {
            self.nextButton.isEnabled = true;
            self.hideIndicator();
            self.dismissView();
        });

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    @objc func domainFieldChanged(domainField: UITextField) {
        self.domainFieldValue = domainField.text;
    }
    
    @IBAction func cancelButtonClicked(_ sender: UIBarButtonItem) {
        dismissView();
    }
    
    @objc func dismissView() {
        task?.cancel();
        task = nil;

        if onAccountAdded != nil {
            navigationController?.dismiss(animated: true, completion: nil);
        } else {
            let newController = navigationController?.popViewController(animated: true);
            if newController == nil || newController != self {
                let emptyDetailController = storyboard!.instantiateViewController(withIdentifier: "emptyDetailViewController");
                self.showDetailViewController(emptyDetailController, sender: self);
            }
        }
    }
    
    func showIndicator() {
        if activityIndicator != nil {
            hideIndicator();
        }
        activityIndicator = UIActivityIndicatorView(style: .gray);
        activityIndicator?.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2);
        activityIndicator!.isHidden = false;
        activityIndicator!.startAnimating();
        view.addSubview(activityIndicator!);
        view.bringSubviewToFront(activityIndicator!);
    }
    
    func hideIndicator() {
        activityIndicator?.stopAnimating();
        activityIndicator?.removeFromSuperview();
        activityIndicator = nil;
    }
}
