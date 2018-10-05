//
// AccountSettingsViewController.swift
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

class AccountSettingsViewController: UITableViewController, EventHandler {
    
    var xmppService: XmppService!;
    
    var account: String! {
        didSet {
            accountJid = BareJID(account);
        }
    }
    var accountJid: BareJID!;
    
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
    
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        navigationItem.title = account;

        xmppService.registerEventHandler(self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE);

        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        
        let config = AccountManager.getAccount(forJid: account);
        enabledSwitch.isOn = config?.active ?? false;
        pushNotificationSwitch.isOn = config?.pushNotifications ?? false;
        archivingEnabledSwitch.isOn = false;
        messageSyncAutomaticSwitch.isEnabled = false;
        pushNotificationsForAwaySwitch.isOn = pushNotificationSwitch.isOn && AccountSettings.PushNotificationsForAway(account).getBool();

        updateView();
        
        let vcard = xmppService.dbVCardsCache.getVCard(for: accountJid);
        update(vcard: vcard);

        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }
    
    override func viewDidAppear(_ animated: Bool) {
        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE);
        NotificationCenter.default.removeObserver(self);
    }

    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.row == 0 && indexPath.section == 1 {
            return nil;
        }
        if indexPath.section == 1 && indexPath.row == 1 && xmppService.getClient(forJid: accountJid)?.state != .connected {
            return nil;
        }
        return indexPath;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false);
        if indexPath.section == 3 && indexPath.row == 2 {
            let controller = TablePickerViewController(style: .grouped);
            let hoursArr = [0.0, 12.0, 24.0, 3*24.0, 7*24.0, 14 * 24.0, 356 * 24.0];
            controller.selected = hoursArr.index(of: AccountSettings.MessageSyncPeriod(account).getDouble()) ?? 0;
            controller.items = hoursArr.map({ (it)->TablePickerViewItemsProtocol in
                return SyncTimeItem(hours: it);
            });
            //controller.selected = 1;
            controller.onSelectionChange = { (_item) -> Void in
                let item = _item as! SyncTimeItem;
                print("select sync of last", item.hours, "hours");
                AccountSettings.MessageSyncPeriod(self.account).set(double: item.hours);
            };
            self.navigationController?.pushViewController(controller, animated: true);
        }
    }
    
    func updateView() {
        let client = xmppService.getClient(forJid: accountJid);
        let pushModule: TigasePushNotificationsModule? = client?.modulesManager.getModule(TigasePushNotificationsModule.ID);
        pushNotificationSwitch.isEnabled = (pushModule?.deviceId != nil) && (pushModule?.isAvailable ?? false);
        pushNotificationsForAwaySwitch.isEnabled = pushNotificationSwitch.isEnabled && (pushModule?.isAvailablePushForAway ?? false);
        
        messageSyncAutomaticSwitch.isOn = AccountSettings.MessageSyncAutomatic(accountJid.description).getBool();
        archivingEnabledSwitch.isEnabled = false;
        
        if (client?.state ?? SocketConnector.State.disconnected == SocketConnector.State.connected), let mamModule: MessageArchiveManagementModule = client?.modulesManager.getModule(MessageArchiveManagementModule.ID) {
            mamModule.retrieveSettings(onSuccess: { (
                defValue, always, never) in
                DispatchQueue.main.async {
                    self.archivingEnabledSwitch.isEnabled = true;
                    self.archivingEnabledSwitch.isOn = defValue == MessageArchiveManagementModule.DefaultValue.always;
                    self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                }
            }, onError: { (error, stanza) in
                DispatchQueue.main.async {
                    self.archivingEnabledSwitch.isOn = false;
                    self.archivingEnabledSwitch.isEnabled = false;
                    self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                }
            })
        }
        messageSyncPeriodLabel.text = SyncTimeItem.descriptionFromHours(hours: AccountSettings.MessageSyncPeriod(account).getDouble());
    }
    
    func handle(event: Event) {
        switch event {
        case is SocketConnector.ConnectedEvent, is SocketConnector.DisconnectedEvent, is StreamManagementModule.ResumedEvent,
             is SessionEstablishmentModule.SessionEstablishmentSuccessEvent, is DiscoveryModule.ServerFeaturesReceivedEvent:
            DispatchQueue.main.async {
                self.updateView();
            }
        default:
            break;
        }
    }
    
    @objc func avatarChanged() {
        let vcard = xmppService.dbVCardsCache.getVCard(for: accountJid);
        DispatchQueue.main.async {
            self.update(vcard: vcard);
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier != nil else {
            return;
        }
        switch segue.identifier! {
        case "EditAccountSegue":
            let destination = segue.destination as! AddAccountController;
            destination.account = account;
        case "EditAccountVCardSegue":
            let destination = segue.destination as! VCardEditViewController;
            destination.account = account;
        case "ShowServerFeatures":
            let destination = segue.destination as! ServerFeaturesViewController;
            destination.account = BareJID(account);
        default:
            break;
        }
    }
        
    @IBAction func enabledSwitchChangedValue(_ sender: AnyObject) {
        if let config = AccountManager.getAccount(forJid: account) {
            config.active = enabledSwitch.isOn;
            AccountSettings.LastError(account).set(string: nil);
            AccountManager.updateAccount(config);
        }
    }
    
    @IBAction func pushNotificationSwitchChangedValue(_ sender: AnyObject) {
        let value = pushNotificationSwitch.isOn;
        if !value {
            self.setPushNotificationsEnabled(forJid: account, value: value);
            pushNotificationsForAwaySwitch.isOn = false;
        } else {
            let alert = UIAlertController(title: "Push Notifications", message: "Tigase iOS Messenger can be automatically notified by compatible XMPP servers about new messages when it is in background or stopped.\nIf enabled, notifications about new messages will be forwarded to our push component and delivered to the device. These notifications will contain message senders jid and part of a message.\nDo you want to enable push notifications?", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: self.enablePushNotifications));
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: {(action) in
                self.pushNotificationSwitch.isOn = false;
            }));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    fileprivate func enablePushNotifications(action: UIAlertAction) {
        let accountJid = self.accountJid!;
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
        if let pushModule: TigasePushNotificationsModule = xmppService.getClient(forJid: accountJid)?.modulesManager.getModule(TigasePushNotificationsModule.ID) {
            pushModule.findPushComponent(completionHandler: {(jid) in
                pushModule.pushServiceJid = jid ?? XmppService.pushServiceJid;
                pushModule.pushServiceNode = nil;
                pushModule.deviceId = Settings.DeviceToken.getString();
                pushModule.enabled = true;
                pushModule.registerDevice(onSuccess: {
                    if let config = AccountManager.getAccount(forJid: accountJid.stringValue) {
                        config.pushServiceNode = pushModule.pushServiceNode
                        config.pushServiceJid = jid;
                        config.pushNotifications = true;
                        AccountManager.updateAccount(config, notifyChange: false);
                    }
                }, onError: { (errorCondition) in
                    DispatchQueue.main.async {
                        self.pushNotificationSwitch.isOn = false;
                        self.pushNotificationsForAwaySwitch.isOn = false;
                    }
                    onError(errorCondition);
                })
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
        guard let pushModule: TigasePushNotificationsModule = xmppService.getClient(forJid: accountJid)?.modulesManager.getModule(TigasePushNotificationsModule.ID) else {
            return;
        }
        
        guard let serviceJid = pushModule.pushServiceJid, let node = pushModule.pushServiceNode else {
            return;
        }
        pushModule.enable(serviceJid: serviceJid, node: node, enableForAway: self.pushNotificationsForAwaySwitch.isOn, onSuccess: { (stanza) in
            print("PUSH enabled!");
            DispatchQueue.main.async {
                guard self.pushNotificationsForAwaySwitch.isOn else {
                    return;
                }
                let syncPeriod = AccountSettings.MessageSyncPeriod(self.account).getDouble();
                if !AccountSettings.MessageSyncAutomatic(self.account).getBool() || syncPeriod < 12 {
                    let alert = UIAlertController(title: "Enable automatic message synchronization", message: "For best experience it is suggested to enable Message Archving with automatic message synchronization of at least last 12 hours.\nDo you wish to do this now?", preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                    alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(action) in
                        AccountSettings.MessageSyncAutomatic(self.account).set(bool: true);
                        if (syncPeriod < 12) {
                            AccountSettings.MessageSyncPeriod(self.account).set(double: 12.0);
                        }
                        self.updateView();
                    }));
                    self.present(alert, animated: true, completion: nil);
                }
            }
        }, onError: {(errorCondition) in
            DispatchQueue.main.async {
                self.pushNotificationsForAwaySwitch.isOn = !self.pushNotificationsForAwaySwitch.isOn;
                AccountSettings.PushNotificationsForAway(self.account).set(bool: self.pushNotificationsForAwaySwitch.isOn);
            }
        });
    }
    
    func setPushNotificationsEnabled(forJid account: String, value: Bool) {
        if let config = AccountManager.getAccount(forJid: account) {
            config.pushNotifications = pushNotificationSwitch.isOn;
            AccountManager.updateAccount(config);
        }
    }
    
    @IBAction func archivingSwitchChangedValue(_ sender: Any) {
        let client = xmppService.getClient(forJid: accountJid);
        if let mamModule: MessageArchiveManagementModule = client?.modulesManager.getModule(MessageArchiveManagementModule.ID) {
            let defValue = archivingEnabledSwitch.isOn ? MessageArchiveManagementModule.DefaultValue.always : MessageArchiveManagementModule.DefaultValue.never;
            mamModule.retrieveSettings(onSuccess: { (oldDefValue, always, never) in
                mamModule.updateSettings(defaultValue: defValue, always: always, never: never, onSuccess: { (newDefValue, always1, never1)->Void in
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = newDefValue == MessageArchiveManagementModule.DefaultValue.always;
                        self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                    }
                }, onError: {(error,stanza)->Void in
                    DispatchQueue.main.async {
                        self.archivingEnabledSwitch.isOn = oldDefValue == MessageArchiveManagementModule.DefaultValue.always;
                        self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                    }
                });
            }, onError: {(error, stanza)->Void in
                DispatchQueue.main.async {
                    self.archivingEnabledSwitch.isOn = !self.archivingEnabledSwitch.isOn;
                    self.messageSyncAutomaticSwitch.isEnabled = self.archivingEnabledSwitch.isOn;
                }
            });
        }
    }
    
    @IBAction func messageSyncAutomaticSwitchChangedValue(_ sender: Any) {
        AccountSettings.MessageSyncAutomatic(accountJid.description).set(bool: self.messageSyncAutomaticSwitch.isOn);
    }
    
    
    func update(vcard: VCard?) {
        avatarView.image = xmppService.avatarManager.getAvatar(for: accountJid, account: accountJid);
        
        if let fn = vcard?.fn {
            fullNameTextView.text = fn;
        } else if let surname = vcard?.surname, let given = vcard?.givenName {
            fullNameTextView.text = "\(given) \(surname)";
        } else {
            fullNameTextView.text = account;
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
