//
// RegisterAccountController.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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
import Foundation

import UIKit
import Martin
import Combine

class RegisterAccountController: DataFormController {
    
    @IBOutlet var nextButton: UIBarButtonItem!
    
    var domain: String? = nil;
    
    var domainFieldValue: String? = nil;

    let trustedServers = [ "tigase.im", "sure.im", "jabber.today" ];
    
    var task: InBandRegistrationModule.AccountRegistrationTask?;
    
    var activityIndicator: UIActivityIndicatorView!;
    
    var onAccountAdded: (() -> Void)?;
    
    private var lockAccount: Bool = false;
    var account: BareJID? = nil;
    var password: String? = nil;
    var preauth: String? = nil;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        passwordSuggestNew = false;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if let account = self.account {
            self.lockAccount = self.account?.localPart != nil;
            DispatchQueue.main.async {
                self.updateDomain(account.domain);
            }
        }
        super.viewWillAppear(animated);
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        onAccountAdded = nil;
        super.viewWillDisappear(animated);
    }
    
    func updateDomain(_ newValue: String?) {
        if newValue != nil && !newValue!.isEmpty && domain != newValue {
            nextButton.isEnabled = false;
            nextButton.title = NSLocalizedString("Register", comment: "button label");
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
                return NSLocalizedString("Preferred domain name", comment: "section label");
            case 1:
                return NSLocalizedString("Trusted servers", comment: "section label");
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
        
        let cell = super.tableView(tableView, cellForRowAt: indexPath);
        if #available(iOS 11.0, *) {
            let fieldName = form!.visibleFieldNames[indexPath.row];
            if fieldName == "username", let c = cell as? TextSingleFieldCell {
                c.uiTextField.isEnabled = !self.lockAccount;
                c.uiTextField?.textContentType = .username;
            }
        }
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard domain != nil else {
            switch section {
            case 0:
                return NSLocalizedString("If you don't know any XMPP server domain names, then select one of our trusted servers.", comment: "section footer")
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
        guard let jid = self.account else {
            return;
        }
        
        var account = AccountManager.getAccount(for: jid) ?? AccountManager.Account(name: jid);
        account.acceptCertificate(acceptedCertificate);
        var cancellables: Set<AnyCancellable> = [];
        do {
            account.password = self.password!;
            try AccountManager.save(account: account);
            self.onAccountAdded?();
            self.dismissView();
            (UIApplication.shared.delegate as? AppDelegate)?.showSetup(value: false);
        } catch {
            cancellables.removeAll();
            let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: NSLocalizedString("It was not possible to save account details", comment: "alert title"), preferredStyle: .alert);
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    func retrieveRegistrationForm(domain: String) {
        let onForm = {(form: JabberDataElement, bob: [BobData], task: InBandRegistrationModule.AccountRegistrationTask)->Void in
            DispatchQueue.main.async {
                self.nextButton.isEnabled = true;
                self.hideIndicator();
                if let accountField = form.getField(named: "username") as? TextSingleField, accountField.value?.isEmpty ?? true {
                    accountField.value = self.account?.localPart;
                }
                self.bob = bob;
                self.form = form;
                
                self.tableView.insertSections(IndexSet(0..<(form.visibleFieldNames.count + 1)), with: .fade);
            }
        };
        let client: XMPPClient? = nil;
        self.task = InBandRegistrationModule.AccountRegistrationTask(client: client, domainName: domain, preauth: self.preauth, onForm: onForm, sslCertificateValidator: nil, onCertificateValidationError: self.onCertificateError, completionHandler: { result in
            switch result {
            case .success:
                let certData: SslCertificateInfo? = self.task?.getAcceptedCertificate();
                DispatchQueue.main.async {
                    self.saveAccount(acceptedCertificate: certData);
                }
            case .failure(let error):
                self.onRegistrationError(error);
            }
        });
    }
    
    func onRegistrationError(_ error: XMPPError) {
        DispatchQueue.main.async {
            self.nextButton.isEnabled = true;
            self.hideIndicator();
        }
        
        var msg = error.message;
        if msg == nil || msg == "Unsuccessful registration attempt" {
            switch error.errorCondition {
            case .feature_not_implemented:
                msg = NSLocalizedString("Registration is not supported by this server", comment: "account registration error");
            case .not_acceptable, .not_allowed:
                msg = NSLocalizedString("Provided values are not acceptable", comment: "account registration error");
            case .conflict:
                msg = NSLocalizedString("User with provided username already exists", comment: "account registration error");
            case .service_unavailable:
                msg = NSLocalizedString("Service is not available at this time.", comment: "account registration error")
            default:
                msg = String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "account registration error"), error.localizedDescription);
            }
        }
        var handler: ((UIAlertAction?)->Void)? = nil;
        
        switch error {
        case .feature_not_implemented, .service_unavailable(_):
            handler = {(action)->Void in
                self.dismissView();
            };
        default:
            break;
        }
                
        let alert = UIAlertController(title: NSLocalizedString("Registration failure", comment: "alert title"), message: msg, preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: handler));
        
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

        if self.view.window?.rootViewController is SetupViewController {
            navigationController?.dismiss(animated: true, completion: nil);
        } else {
            let newController = navigationController?.popViewController(animated: true);
            if newController == nil || newController != self {
                let emptyDetailController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "emptyDetailViewController");
                self.showDetailViewController(emptyDetailController, sender: self);
            }
        }
    }
    
    func showIndicator() {
        if activityIndicator != nil {
            hideIndicator();
        }
        activityIndicator = UIActivityIndicatorView(style: .medium);
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
