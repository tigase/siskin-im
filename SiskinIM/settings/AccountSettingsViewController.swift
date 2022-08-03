//
// AccountSettingsViewController.swift
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

class AccountSettingsViewController: UITableViewController {
    
    var account: BareJID!;
    
    @IBOutlet var avatarView: UIImageView!
    @IBOutlet var fullNameTextView: UILabel!
    @IBOutlet var companyTextView: UILabel!
    @IBOutlet var addressTextView: UILabel!
    
    @IBOutlet var enabledSwitch: UISwitch!
    @IBOutlet var nicknameLabel: UILabel!;
    @IBOutlet var pushNotificationsForAwaySwitch: UISwitch!
    
    @IBOutlet var archivingEnabledSwitch: UISwitch!;
    
    @IBOutlet var omemoFingerprint: UILabel!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        tableView.contentInset = UIEdgeInsets(top: -1, left: 0, bottom: 0, right: 0);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        navigationItem.title = account.stringValue;
        
        AccountManager.accountEventsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] event in
            switch event {
            case .enabled(let account,_), .disabled(let account), .removed(let account):
                if self?.account == account.name {
                    self?.updateView();
                }
            }
        }).store(in: &cancellables);
        
        let config = AccountManager.getAccount(for: account);
        enabledSwitch.isOn = config?.active ?? false;
        nicknameLabel.text = config?.nickname;
        archivingEnabledSwitch.isOn = false;
        pushNotificationsForAwaySwitch.isOn = (config?.pushNotifications ?? false) && AccountSettings.pushNotificationsForAway(for: account);

        updateView();
        
        DBVCardStore.instance.vcard(for: account, completionHandler: { vcard in
            DispatchQueue.main.async {
                self.update(vcard: vcard);
            }
        })

        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
        
        AvatarManager.instance.avatarPublisher(for: .init(account: account, jid: account, mucNickname: nil)).avatarPublisher.receive(on: DispatchQueue.main).assign(to: \.image, on: avatarView).store(in: &cancellables);
        
        XmppService.instance.$connectedClients.map({ [weak self] clients in clients.first(where: { c in c.userBareJid == self?.account }) }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.updateView();
            }
        }).store(in: &cancellables);
        
        let localDeviceId = Int32(bitPattern: AccountSettings.omemoRegistrationId(for: self.account) ?? 0);
        if let omemoIdentity = DBOMEMOStore.instance.identities(forAccount: self.account, andName: self.account.stringValue).first(where: { (identity) -> Bool in
            return identity.address.deviceId == localDeviceId;
        }) {
            var fingerprint = String(omemoIdentity.fingerprint.dropFirst(2));
            var idx = fingerprint.startIndex;
            for _ in 0..<(fingerprint.count / 8) {
                idx = fingerprint.index(idx, offsetBy: 8);
                fingerprint.insert(" ", at: idx);
                idx = fingerprint.index(after: idx);
            }
            omemoFingerprint.text = fingerprint;
        } else {
            omemoFingerprint.text = NSLocalizedString("Key not generated!", comment: "no OMEMO key - not generated yet");
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        cancellables.removeAll();
        super.viewDidDisappear(animated);
    }

    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.row == 0 && indexPath.section == 1 {
            return nil;
        }
        if indexPath.section == 1 && indexPath.row == 1 && XmppService.instance.getClient(for: account)?.state != .connected() {
            return nil;
        }
        return indexPath;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false);
        if indexPath.section == 1 && indexPath.row == 3 {
            let controller = UIAlertController(title: NSLocalizedString("Nickname", comment: "alert title"), message: NSLocalizedString("Enter default nickname to use in chats", comment: "alert body"), preferredStyle: .alert);
            controller.addTextField(configurationHandler: { textField in
                textField.text = AccountManager.getAccount(for: self.account)?.nickname ?? "";
            });
            controller.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                let nickname = controller.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines);
                if var account = AccountManager.getAccount(for: self.account) {
                    account.nickname = nickname;
                    try? AccountManager.save(account: account, reconnect: false);
                    self.nicknameLabel.text = account.nickname;
                }
            }))
            self.navigationController?.present(controller, animated: true, completion: nil);
        }
        if indexPath.section == 5 && indexPath.row == 0 {
            self.deleteAccount();
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return nil;
        }
        return super.tableView(tableView, titleForHeaderInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 1.0;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }
    
    func updateView() {
        let client = XmppService.instance.getClient(for: account);
        if let pushModule = client?.module(.push) as? SiskinPushNotificationsModule {
            pushNotificationsForAwaySwitch.isEnabled = pushModule.isEnabled && pushModule.isSupported(extension: TigasePushNotificationsModule.PushForAway.self);
        } else {
            pushNotificationsForAwaySwitch.isEnabled = false;
        }
        
        archivingEnabledSwitch.isEnabled = false;
        
        if let mamModule = client?.module(.mam), mamModule.isAvailable {
            mamModule.retrieveSettings(completionHandler: { result in
                switch result {
                case .success(let settings):
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isEnabled = true;
                        self.archivingEnabledSwitch.isOn = settings.defaultValue == .always;
                    }
                case .failure(_):
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = false;
                        self.archivingEnabledSwitch.isEnabled = false;
                    }
                }
            })
        }
    }
            
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier != nil else {
            return;
        }
        switch segue.identifier! {
        case "AccountQRCodeController":
            let destination = segue.destination as! AccountQRCodeController;
            destination.account = account;
        case "EditAccountSegue":
            let destination = segue.destination as! AddAccountController;
            destination.account = account.stringValue;
        case "EditAccountVCardSegue":
            let destination = segue.destination as! VCardEditViewController;
            destination.client = XmppService.instance.getClient(for: account);
        case "ShowServerFeatures":
            let destination = segue.destination as! ServerFeaturesViewController;
            destination.client = XmppService.instance.getClient(for: account);
        case "ManageOMEMOFingerprints":
            let destination = segue.destination as! OMEMOFingerprintsController;
            destination.account = account;
        default:
            break;
        }
    }
        
    @IBAction func enabledSwitchChangedValue(_ sender: AnyObject) {
        let newState = enabledSwitch.isOn;
        let account = self.account!;
        AccountSettings.lastError(for: account, value: nil);
        
        if newState {
            if var config = AccountManager.getAccount(for: account) {
                config.active = newState
                AccountSettings.lastError(for: account, value: nil);
                try? AccountManager.save(account: config);
            }
        } else {
            if let client = XmppService.instance.getClient(for: account), client.isConnected, let pushModule = client.module(.push) as? SiskinPushNotificationsModule, pushModule.isEnabled {
                self.enabledSwitch.isEnabled = false;
                pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                    if var config = AccountManager.getAccount(for: account) {
                        config.active = newState;
                        AccountSettings.lastError(for: account, value: nil);
                        try? AccountManager.save(account: config);
                    }
                    self.enabledSwitch.isEnabled = true;
                })
            } else {
                if var config = AccountManager.getAccount(for: account) {
                    config.active = enabledSwitch.isOn;
                    AccountSettings.lastError(for: account, value: nil);
                    try? AccountManager.save(account: config);
                }
            }
        }
    }
    
    @IBAction func pushNotificationsForAwaySwitchChangedValue(_ sender: Any) {
        AccountSettings.pushNotificationsForAway(for: account, value: self.pushNotificationsForAwaySwitch.isOn);

        guard let pushModule = XmppService.instance.getClient(for: account)?.module(.push) as? SiskinPushNotificationsModule else {
            return;
        }
        
        guard let pushSettings = pushModule.pushSettings else {
            return;
        }
        pushModule.reenable(pushSettings: pushSettings, completionHandler: { (result) in
            switch result {
            case .success(_):
                DispatchQueue.main.async {
                    guard self.pushNotificationsForAwaySwitch.isOn else {
                        return;
                    }
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.pushNotificationsForAwaySwitch.isOn = !self.pushNotificationsForAwaySwitch.isOn;
                    AccountSettings.pushNotificationsForAway(for: self.account, value: self.pushNotificationsForAwaySwitch.isOn);
                }
            }
        });
    }
        
    @IBAction func archivingSwitchChangedValue(_ sender: Any) {
        if let mamModule = XmppService.instance.getClient(for: account)?.module(.mam){
            let defValue = archivingEnabledSwitch.isOn ? MessageArchiveManagementModule.DefaultValue.always : MessageArchiveManagementModule.DefaultValue.never;
            mamModule.retrieveSettings(completionHandler: { result in
                switch result {
                case .success(let oldSettings):
                    var newSettings = oldSettings;
                    newSettings.defaultValue = defValue;
                    mamModule.updateSettings(settings: newSettings, completionHandler: { result in
                        switch result {
                        case .success(let newSettings):
                            DispatchQueue.main.async {
                                self.archivingEnabledSwitch.isOn = newSettings.defaultValue == .always;
                            }
                        case .failure(_):
                            DispatchQueue.main.async {
                                self.archivingEnabledSwitch.isOn = oldSettings.defaultValue == .always;
                            }
                        }
                    });
                case .failure(_):
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = !self.archivingEnabledSwitch.isOn;
                    }
                }
            });
        }
    }
        
    func update(vcard: VCard?) {
        if let fn = vcard?.fn {
            fullNameTextView.text = fn;
        } else if let surname = vcard?.surname, let given = vcard?.givenName {
            fullNameTextView.text = "\(given) \(surname)";
        } else {
            fullNameTextView.text = account.stringValue;
        }
        
        let company = vcard?.organizations.first?.name;
        let role = vcard?.role;
        if role != nil && company != nil {
            companyTextView.text = "\(role!) at \(company!)";
            companyTextView.isHidden = false;
        } else if company != nil {
            companyTextView.text = company;
            companyTextView.isHidden = false;
        } else if role != nil {
            companyTextView.text = role;
            companyTextView.isHidden = false;
        } else {
            companyTextView.isHidden = true;
        }
        
        let addresses = vcard?.addresses.filter { (addr) -> Bool in
            return !addr.isEmpty;
        };
        
        if let address = addresses?.first {
            var tmp = [String]();
            if address.street != nil {
                tmp.append(address.street!);
            }
            if address.locality != nil {
                tmp.append(address.locality!);
            }
            if address.country != nil {
                tmp.append(address.country!);
            }
            addressTextView.text = tmp.joined(separator: ", ");
        } else {
            addressTextView.text = nil;
        }
    }
    
    func deleteAccount() {
        guard let account = self.account, var config = AccountManager.getAccount(for: account) else {
            return;
        }
        
        let removeAccount: (BareJID, Bool)->Void = { account, fromServer in
            if fromServer {
                if let client = XmppService.instance.getClient(for: account), client.state == .connected() {
                    let regModule = client.modulesManager.register(InBandRegistrationModule());
                    regModule.unregister(completionHander: { (result) in
                        DispatchQueue.main.async() {
                            try? AccountManager.deleteAccount(for: account);
                            self.navigationController?.popViewController(animated: true);
                        }
                    });
                } else {
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: NSLocalizedString("Account removal", comment: "alert title"), message: NSLocalizedString("Could not delete account as it was not possible to connect to the XMPP server. Please try again later.", comment: "alert body"), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                            self.tableView.reloadData();
                        }));
                        self.present(alert, animated: true, completion: nil);
                    }
                }
            } else {
                DispatchQueue.main.async {
                    try? AccountManager.deleteAccount(for: account);
                    self.navigationController?.popViewController(animated: true);
                }
            }
        };
        
        self.askAboutAccountRemoval(account: account, atRow: IndexPath(row: 0, section: 5), completionHandler: { result in
            switch result {
            case .success(let removeFromServer):
                if let pushSettings = config.pushSettings {
                    if let client = XmppService.instance.getClient(for: account), client.state == .connected(), let pushModule = client.module(.push) as? SiskinPushNotificationsModule {
                        pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                            switch result {
                            case .success(_):
                                // now remove the account...
                                removeAccount(account, removeFromServer)
                                break;
                            case .failure(_):
                                PushEventHandler.unregisterDevice(from: pushSettings.jid.bareJid, account: account, deviceId: pushSettings.deviceId, completionHandler: { result in
                                    config.pushSettings = nil;
                                    try? AccountManager.save(account: config);
                                    DispatchQueue.main.async {
                                        switch result {
                                        case .success(_):
                                            removeAccount(account, removeFromServer);
                                        case .failure(_):
                                            let alert = UIAlertController(title: NSLocalizedString("Account removal", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Push notifications are enabled for %@. They need to be disabled before account can be removed and it is not possible to at this time. Please try again later.", comment: "alert body"), account.stringValue), preferredStyle: .alert);
                                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                                            self.present(alert, animated: true, completion: nil);
                                        }
                                    }
                                })
                            }
                        });
                    } else {
                        PushEventHandler.unregisterDevice(from: pushSettings.jid.bareJid, account: account, deviceId: pushSettings.deviceId, completionHandler: { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(_):
                                    config.pushSettings = nil;
                                    try? AccountManager.save(account: config);
                                    removeAccount(account, removeFromServer);
                                case .failure(_):
                                    let alert = UIAlertController(title: NSLocalizedString("Account removal", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Push notifications are enabled for %@. They need to be disabled before account can be removed and it is not possible to at this time. Please try again later.", comment: "alert body"), account.stringValue), preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                                    self.present(alert, animated: true, completion: nil);
                                }
                            }
                        })
                    }
                } else {
                    removeAccount(account, removeFromServer);
                }
            case .failure(_):
                break;
            }
        })
    }
        
    func askAboutAccountRemoval(account: BareJID, atRow indexPath: IndexPath, completionHandler: @escaping (Result<Bool, Error>)->Void) {
        let client = XmppService.instance.getClient(for: account)
        let alert = UIAlertController(title: NSLocalizedString("Account removal", comment: "alert title"), message: client != nil ? NSLocalizedString("Should account be removed from server as well?", comment: "alert body") : NSLocalizedString("Remove account from application?", comment: "alert body"), preferredStyle: .actionSheet);
        if client?.state == .connected() {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Remove from server", comment: "button label"), style: .destructive, handler: { (action) in
                completionHandler(.success(true));
            }));
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Remove from application", comment: "button label"), style: .default, handler: { (action) in
            completionHandler(.success(false));
        }));
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .default, handler: nil));
        alert.popoverPresentationController?.sourceView = self.tableView;
        alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

        self.present(alert, animated: true, completion: nil);
    }

}
