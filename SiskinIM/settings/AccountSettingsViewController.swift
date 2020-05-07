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
import TigaseSwift

class AccountSettingsViewController: UITableViewController {
    
    var account: BareJID!;
    
    @IBOutlet var avatarView: UIImageView!
    @IBOutlet var fullNameTextView: UILabel!
    @IBOutlet var companyTextView: UILabel!
    @IBOutlet var addressTextView: UILabel!
    
    @IBOutlet var enabledSwitch: UISwitch!
    @IBOutlet var pushNotificationSwitch: UISwitch!;
    @IBOutlet var pushNotificationsForAwaySwitch: UISwitch!
    
    @IBOutlet var archivingEnabledSwitch: UISwitch!;
    @IBOutlet var messageSyncAutomaticSwitch: UISwitch!;
    @IBOutlet var messageSyncPeriodLabel: UILabel!;
    
    @IBOutlet var omemoFingerprint: UILabel!;
    
    override func viewDidLoad() {
        tableView.contentInset = UIEdgeInsets(top: -1, left: 0, bottom: 0, right: 0);
        NotificationCenter.default.addObserver(self, selector: #selector(refreshOnNotification), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(refreshOnNotification), name: DiscoEventHandler.ACCOUNT_FEATURES_RECEIVED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(refreshOnNotification), name: DiscoEventHandler.SERVER_FEATURES_RECEIVED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        navigationItem.title = account.stringValue;

        
        let config = AccountManager.getAccount(for: account);
        enabledSwitch.isOn = config?.active ?? false;
        pushNotificationSwitch.isOn = config?.pushNotifications ?? false;
        archivingEnabledSwitch.isOn = false;
        messageSyncAutomaticSwitch.isEnabled = false;
        pushNotificationsForAwaySwitch.isOn = pushNotificationSwitch.isOn && AccountSettings.PushNotificationsForAway(account).getBool();

        updateView();
        
        let vcard = XmppService.instance.dbVCardsCache.getVCard(for: account);
        update(vcard: vcard);

        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
        
        let localDeviceId = Int32(bitPattern: AccountSettings.omemoRegistrationId(self.account).getUInt32() ?? 0);
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
            omemoFingerprint.text = "Key not generated!";
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
    }

    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.row == 0 && indexPath.section == 1 {
            return nil;
        }
        if indexPath.section == 1 && indexPath.row == 1 && XmppService.instance.getClient(for: account)?.state != .connected {
            return nil;
        }
        return indexPath;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false);
        if indexPath.section == 3 && indexPath.row == 2 {
            let controller = TablePickerViewController(style: .grouped);
            let hoursArr = [0.0, 12.0, 24.0, 3*24.0, 7*24.0, 14 * 24.0, 356 * 24.0];
            controller.selected = hoursArr.firstIndex(of: AccountSettings.messageSyncPeriod(account).getDouble()) ?? 0;
            controller.items = hoursArr.map({ (it)->TablePickerViewItemsProtocol in
                return SyncTimeItem(hours: it);
            });
            //controller.selected = 1;
            controller.onSelectionChange = { (_item) -> Void in
                let item = _item as! SyncTimeItem;
                print("select sync of last", item.hours, "hours");
                AccountSettings.messageSyncPeriod(self.account).set(double: item.hours);
            };
            self.navigationController?.pushViewController(controller, animated: true);
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
        let pushModule: SiskinPushNotificationsModule? = client?.modulesManager.getModule(SiskinPushNotificationsModule.ID);
        pushNotificationSwitch.isEnabled = (PushEventHandler.instance.deviceId != nil) && (pushModule?.isAvailable ?? false);
        pushNotificationsForAwaySwitch.isEnabled = pushNotificationSwitch.isEnabled && (pushModule?.isSupported(extension: TigasePushNotificationsModule.PushForAway.self) ?? false);
        
        messageSyncAutomaticSwitch.isOn = AccountSettings.messageSyncAuto(account).getBool();
        archivingEnabledSwitch.isEnabled = false;
        
        if (client?.state ?? SocketConnector.State.disconnected == SocketConnector.State.connected), let mamModule: MessageArchiveManagementModule = client?.modulesManager.getModule(MessageArchiveManagementModule.ID) {
            mamModule.retrieveSettings(completionHandler: { result in
                switch result {
                case .success(let defValue, _, _):
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isEnabled = true;
                        self.archivingEnabledSwitch.isOn = defValue == MessageArchiveManagementModule.DefaultValue.always;
                        self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                    }
                case .failure(_, _):
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = false;
                        self.archivingEnabledSwitch.isEnabled = false;
                        self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                    }
                }
            })
        }
        messageSyncPeriodLabel.text = SyncTimeItem.descriptionFromHours(hours: AccountSettings.messageSyncPeriod(account).getDouble());
    }
    
    @objc func avatarChanged() {
        let vcard = XmppService.instance.dbVCardsCache.getVCard(for: account);
        DispatchQueue.main.async {
            self.update(vcard: vcard);
        }
    }
    
    @objc func refreshOnNotification() {
        DispatchQueue.main.async {
            self.updateView();
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
            destination.account = account;
        case "ShowServerFeatures":
            let destination = segue.destination as! ServerFeaturesViewController;
            destination.account = account;
        case "ManageOMEMOFingerprints":
            let destination = segue.destination as! OMEMOFingerprintsController;
            destination.account = account;
        default:
            break;
        }
    }
        
    @IBAction func enabledSwitchChangedValue(_ sender: AnyObject) {
        if let config = AccountManager.getAccount(for: account!) {
            config.active = enabledSwitch.isOn;
            AccountSettings.LastError(account).set(string: nil);
            AccountManager.save(account: config);
        }
    }
    
    @IBAction func pushNotificationSwitchChangedValue(_ sender: AnyObject) {
        let value = pushNotificationSwitch.isOn;
        if !value {
            self.setPushNotificationsEnabled(forJid: account, value: value);
            pushNotificationsForAwaySwitch.isOn = false;
        } else {
            let alert = UIAlertController(title: "Push Notifications", message: "Siskin IM can be automatically notified by compatible XMPP servers about new messages when it is in background or stopped.\nIf enabled, notifications about new messages will be forwarded to our push component and delivered to the device. These notifications may contain message senders jid and part of a message.\nDo you want to enable push notifications?", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: self.enablePushNotifications));
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: {(action) in
                self.pushNotificationSwitch.isOn = false;
            }));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    fileprivate func enablePushNotifications(action: UIAlertAction) {
        let accountJid = self.account!;
        let onError = { (_ errorCondition: ErrorCondition?) in
            DispatchQueue.main.async {
                var userInfo: [AnyHashable:Any] = ["account": accountJid];
                if errorCondition != nil {
                    userInfo["errorCondition"] = errorCondition;
                }
                NotificationCenter.default.post(name: Notification.Name("pushNotificationsRegistrationFailed"), object: self, userInfo: userInfo);
            }
        }
        // let's check if push notifications component is accessible
        if let pushModule: SiskinPushNotificationsModule = XmppService.instance.getClient(forJid: accountJid)?.modulesManager.getModule(SiskinPushNotificationsModule.ID), let deviceId = PushEventHandler.instance.deviceId {
            pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: PushEventHandler.instance.pushkitDeviceId, completionHandler: { result in
                switch result {
                case .success(_):
                    break;
                case .failure(let errorCondition):
                    DispatchQueue.main.async {
                        self.pushNotificationSwitch.isOn = false;
                        self.pushNotificationsForAwaySwitch.isOn = false;
                    }
                    onError(errorCondition);
                }
            });
        } else {
            pushNotificationSwitch.isOn = false;
            pushNotificationsForAwaySwitch.isOn = false;
            onError(ErrorCondition.service_unavailable);
        }
    }
    
    @IBAction func pushNotificationsForAwaySwitchChangedValue(_ sender: Any) {
        guard self.pushNotificationSwitch.isOn else {
            self.pushNotificationsForAwaySwitch.isOn = false;
            return;
        }
        
        AccountSettings.PushNotificationsForAway(account).set(bool: self.pushNotificationsForAwaySwitch.isOn);
        guard let pushModule: SiskinPushNotificationsModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(SiskinPushNotificationsModule.ID) else {
            return;
        }
        
        guard let pushSettings = pushModule.pushSettings else {
            return;
        }
        pushModule.reenable(pushSettings: pushSettings, completionHandler: { (result) in
            switch result {
            case .success(_):
                print("PUSH enabled!");
                DispatchQueue.main.async {
                    guard self.pushNotificationsForAwaySwitch.isOn else {
                        return;
                    }
                    let syncPeriod = AccountSettings.messageSyncPeriod(self.account).getDouble();
                    if !AccountSettings.messageSyncAuto(self.account).getBool() || syncPeriod < 12 {
                        let alert = UIAlertController(title: "Enable automatic message synchronization", message: "For best experience it is suggested to enable Message Archving with automatic message synchronization of at least last 12 hours.\nDo you wish to do this now?", preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                        alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(action) in
                            AccountSettings.messageSyncAuto(self.account).set(bool: true);
                            if (syncPeriod < 12) {
                                AccountSettings.messageSyncPeriod(self.account).set(double: 12.0);
                            }
                            self.updateView();
                        }));
                        self.present(alert, animated: true, completion: nil);
                    }
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.pushNotificationsForAwaySwitch.isOn = !self.pushNotificationsForAwaySwitch.isOn;
                    AccountSettings.PushNotificationsForAway(self.account).set(bool: self.pushNotificationsForAwaySwitch.isOn);
                }
            }
        });
    }
    
    func setPushNotificationsEnabled(forJid account: BareJID, value: Bool) {
        if let config = AccountManager.getAccount(for: account) {
            config.pushNotifications = pushNotificationSwitch.isOn;
            AccountManager.save(account: config);
        }
    }
    
    @IBAction func archivingSwitchChangedValue(_ sender: Any) {
        let client = XmppService.instance.getClient(forJid: account);
        if let mamModule: MessageArchiveManagementModule = client?.modulesManager.getModule(MessageArchiveManagementModule.ID) {
            let defValue = archivingEnabledSwitch.isOn ? MessageArchiveManagementModule.DefaultValue.always : MessageArchiveManagementModule.DefaultValue.never;
            mamModule.retrieveSettings(completionHandler: { result in
                switch result {
                case .success(let oldDefValue, let always, let never):
                    mamModule.updateSettings(defaultValue: defValue, always: always, never: never, completionHandler: { result in
                        switch result {
                        case .success(let newDefValue, _, _):
                            DispatchQueue.main.async {
                                self.archivingEnabledSwitch.isOn = newDefValue == MessageArchiveManagementModule.DefaultValue.always;
                                self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                            }
                        case .failure(_, _):
                            DispatchQueue.main.async {
                                self.archivingEnabledSwitch.isOn = oldDefValue == MessageArchiveManagementModule.DefaultValue.always;
                                self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                            }
                        }
                    });
                case .failure(_, _):
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = !self.archivingEnabledSwitch.isOn;
                        self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                    }
                }
            });
        }
    }
    
    @IBAction func messageSyncAutomaticSwitchChangedValue(_ sender: Any) {
        AccountSettings.messageSyncAuto(account).set(bool: self.messageSyncAutomaticSwitch.isOn);
    }
    
    
    func update(vcard: VCard?) {
        avatarView.image = AvatarManager.instance.avatar(for: account, on: account) ?? AvatarManager.instance.defaultAvatar;
        
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
    
    class SyncTimeItem: TablePickerViewItemsProtocol {
        
        public static func descriptionFromHours(hours: Double) -> String {
            if (hours == 0) {
                return "Nothing";
            } else if (hours >= 24*365) {
                return "All";
            } else if (hours > 24) {
                return "Last \(Int(hours/24)) days"
            } else {
                return "Last \(Int(hours)) hours";
            }
        }
        
        let description: String;
        let hours: Double;
        
        init(hours: Double) {
            self.hours = hours;
            self.description = SyncTimeItem.descriptionFromHours(hours: hours);
        }
        
    }
}
