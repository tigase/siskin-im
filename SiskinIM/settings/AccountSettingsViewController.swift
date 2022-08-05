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
        navigationItem.title = account.description;
        
        AccountManager.accountEventsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] event in
            switch event {
            case .enabled(let account,_), .disabled(let account), .removed(let account):
                if self?.account == account.name {
                    self?.updateView();
                }
            }
        }).store(in: &cancellables);
        
        let config = AccountManager.account(for: account);
        enabledSwitch.isOn = config?.enabled ?? false;
        nicknameLabel.text = config?.nickname;
        archivingEnabledSwitch.isOn = false;
        pushNotificationsForAwaySwitch.isOn = (config?.push.registration != nil) && config?.push.enableForAway ?? false;

        updateView();
        
        Task {
            let vcard = await DBVCardStore.instance.vcard(for: account);
            self.update(vcard: vcard);
        }

        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
        
        AvatarManager.instance.avatarPublisher(for: .init(account: account, jid: account, mucNickname: nil)).avatarPublisher.receive(on: DispatchQueue.main).assign(to: \.image, on: avatarView).store(in: &cancellables);
        
        XmppService.instance.$connectedClients.map({ [weak self] clients in clients.first(where: { c in c.userBareJid == self?.account }) }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.updateView();
            }
        }).store(in: &cancellables);
        
        let localDeviceId = Int32(bitPattern: config?.omemoDeviceId ?? 0);
        if let omemoIdentity = DBOMEMOStore.instance.identities(forAccount: self.account, andName: self.account.description).first(where: { (identity) -> Bool in
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
                textField.text = AccountManager.account(for: self.account)?.nickname ?? "";
            });
            controller.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                let nickname = controller.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines);
                try? AccountManager.modifyAccount(for: self.account, { account in
                    account.nickname = nickname;
                })
                self.nicknameLabel.text = nickname;
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
            pushNotificationsForAwaySwitch.isEnabled = AccountManager.account(for: account)?.push.registration != nil && pushModule.isSupported(extension: TigasePushNotificationsModule.PushForAway.self);
        } else {
            pushNotificationsForAwaySwitch.isEnabled = false;
        }
        
        archivingEnabledSwitch.isEnabled = false;
        
        if let mamModule = client?.module(.mam), mamModule.isAvailable {
            Task {
                do {
                    let settings = try await mamModule.settings();
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isEnabled = true;
                        self.archivingEnabledSwitch.isOn = settings.defaultValue == .always;
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = false;
                        self.archivingEnabledSwitch.isEnabled = false;
                    }
                }
            }
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
            destination.account = account.description;
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
        
        if newState {
            try? AccountManager.modifyAccount(for: account, { config in
                config.enabled = newState;
            })
        } else {
            if let client = XmppService.instance.getClient(for: account), client.isConnected, let pushModule = client.module(.push) as? SiskinPushNotificationsModule, let registration = AccountManager.account(for: account)?.push.registration {
                self.enabledSwitch.isEnabled = false;
                Task {
                    try? await pushModule.unregisterDeviceAndDisable(registration: registration);
                    try? AccountManager.modifyAccount(for: account, { config in
                        config.enabled = newState;
                        config.push = .init();
                    })
                    self.enabledSwitch.isEnabled = true;
                }
            } else {
                try? AccountManager.modifyAccount(for: account, { config in
                    config.enabled = newState;
                })
            }
        }
    }
    
    @IBAction func pushNotificationsForAwaySwitchChangedValue(_ sender: Any) {
        let newValue = pushNotificationsForAwaySwitch.isOn;
        try? AccountManager.modifyAccount(for: account, { account in
            account.push.enableForAway = newValue;
        })

        guard let pushModule = XmppService.instance.getClient(for: account)?.module(.push) as? SiskinPushNotificationsModule else {
            return;
        }
        
        guard let pushSettings = AccountManager.account(for: account)?.push else {
            return;
        }
        Task {
            do {
                try await pushModule.enable(settings: pushSettings);
            } catch {
                await MainActor.run(body: {
                    self.pushNotificationsForAwaySwitch.isOn = !self.pushNotificationsForAwaySwitch.isOn;
                    try? AccountManager.modifyAccount(for: account, { account in
                        account.push.enableForAway = !newValue;
                    })
                })
            }
        }
    }
        
    @IBAction func archivingSwitchChangedValue(_ sender: Any) {
        if let mamModule = XmppService.instance.getClient(for: account)?.module(.mam){
            let defValue = archivingEnabledSwitch.isOn ? MessageArchiveManagementModule.DefaultValue.always : MessageArchiveManagementModule.DefaultValue.never;
            Task {
                do {
                    let oldSettings = try await mamModule.settings();
                    do {
                        var settings = oldSettings;
                        settings.defaultValue = defValue;
                        let newSettings = try await mamModule.settings(settings);
                        DispatchQueue.main.async {
                            self.archivingEnabledSwitch.isOn = newSettings.defaultValue == .always;
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.archivingEnabledSwitch.isOn = oldSettings.defaultValue == .always;
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = !self.archivingEnabledSwitch.isOn;
                    }
                }
            }
        }
    }
        
    @MainActor
    func update(vcard: VCard?) {
        if let fn = vcard?.fn {
            fullNameTextView.text = fn;
        } else if let surname = vcard?.surname, let given = vcard?.givenName {
            fullNameTextView.text = "\(given) \(surname)";
        } else {
            fullNameTextView.text = account.description;
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
        guard let account = self.account, var config = AccountManager.account(for: account) else {
            return;
        }
        
        let removeAccount: (BareJID, Bool)->Void = { account, fromServer in
            if fromServer {
                if let client = XmppService.instance.getClient(for: account), client.state == .connected() {
                    Task {
                        let regModule = client.modulesManager.register(InBandRegistrationModule());
                        _ = try? await regModule.unregister();
                        await MainActor.run(body: {
                            try? AccountManager.deleteAccount(for: account);
                            self.navigationController?.popViewController(animated: true);
                        })
                    }
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
                if let registration = config.push.registration {
                    if let client = XmppService.instance.getClient(for: account), client.state == .connected(), let pushModule = client.module(.push) as? SiskinPushNotificationsModule {
                        Task {
                            do {
                                try await pushModule.unregisterDeviceAndDisable(registration: registration);
                                try? AccountManager.modifyAccount(for: account, { config in
                                    config.push = .init();
                                })
                                removeAccount(account, removeFromServer);
                            } catch {
                                do {
                                    try await PushEventHandler.unregisterDevice(from: registration.jid.bareJid, account: account, deviceId: registration.deviceId);
                                    try? AccountManager.modifyAccount(for: account, { config in
                                        config.push = .init();
                                    })
                                    removeAccount(account, removeFromServer);
                                } catch {
                                    await MainActor.run(body: {
                                        let alert = UIAlertController(title: NSLocalizedString("Account removal", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Push notifications are enabled for %@. They need to be disabled before account can be removed and it is not possible to at this time. Please try again later.", comment: "alert body"), account.description), preferredStyle: .alert);
                                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                                        self.present(alert, animated: true, completion: nil);
                                    })
                                }
                            }
                        }
                    } else {
                        Task {
                            do {
                                try await PushEventHandler.unregisterDevice(from: registration.jid.bareJid, account: account, deviceId: registration.deviceId);
                                try? AccountManager.modifyAccount(for: account, { config in
                                    config.push = .init();
                                })
                                removeAccount(account, removeFromServer);
                            } catch {
                                await MainActor.run(body: {
                                    let alert = UIAlertController(title: NSLocalizedString("Account removal", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Push notifications are enabled for %@. They need to be disabled before account can be removed and it is not possible to at this time. Please try again later.", comment: "alert body"), account.description), preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                                    self.present(alert, animated: true, completion: nil);
                                })
                            }
                        }
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
