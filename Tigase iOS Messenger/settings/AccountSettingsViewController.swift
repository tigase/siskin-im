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
    
    var xmppService: XmppService {
        let delegate = UIApplication.shared.delegate as! AppDelegate;
        return delegate.xmppService;
    }
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        navigationItem.title = account;

        xmppService.registerEventHandler(self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE);

        let config = AccountManager.getAccount(forJid: account);
        enabledSwitch.isOn = config?.active ?? false;
        pushNotificationSwitch.isOn = config?.pushNotifications ?? false;

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
    }

    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.row == 0 && indexPath.section == 1 {
            return nil;
        }
        return indexPath;
    }
    
    func updateView() {
        let client = xmppService.getClient(forJid: accountJid);
        let pushModule: TigasePushNotificationsModule? = client?.modulesManager.getModule(TigasePushNotificationsModule.ID);
        pushNotificationSwitch.isEnabled = (pushModule?.deviceId != nil) && (pushModule?.isAvailable ?? false);
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
        default:
            break;
        }
    }
        
    @IBAction func enabledSwitchChangedValue(_ sender: AnyObject) {
        if let config = AccountManager.getAccount(forJid: account) {
            config.active = enabledSwitch.isOn;
            AccountManager.updateAccount(config);
        }
    }
    
    @IBAction func pushNotificationSwitchChangedValue(_ sender: AnyObject) {
        let value = pushNotificationSwitch.isOn;
        if !value {
            self.setPushNotificationsEnabled(forJid: account, value: value);
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
                    }
                    onError(errorCondition);
                })
            });
        } else {
            pushNotificationSwitch.isOn = false;
            onError(ErrorCondition.service_unavailable);
        }
    }
    
    func setPushNotificationsEnabled(forJid account: String, value: Bool) {
        if let config = AccountManager.getAccount(forJid: account) {
            config.pushNotifications = pushNotificationSwitch.isOn;
            AccountManager.updateAccount(config);
        }
    }
    
    
    func update(vcard: VCardModule.VCard?) {
        avatarView.image = xmppService.avatarManager.getAvatar(for: accountJid, account: accountJid);
        
        if let fn = vcard?.fn {
            fullNameTextView.text = fn;
        } else if let family = vcard?.familyName, let given = vcard?.givenName {
            fullNameTextView.text = "\(given) \(family)";
        } else {
            fullNameTextView.text = account;
        }
        
        let company = vcard?.orgName;
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
            return !addr.isEmpty();
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
}
