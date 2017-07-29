//
// TigasePushNotificationsModule.swift
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

import UIKit
import UserNotifications
import TigaseSwift

open class TigasePushNotificationsModule: PushNotificationsModule, EventHandler {
    
    fileprivate static let PUSH_FOR_AWAY_XMLNS = "tigase:push:away:0";
    
    fileprivate var oldDeviceId: String? = nil;
    open var deviceId: String? = "?" {
        willSet {
            guard deviceId != "?" && deviceId != newValue && oldDeviceId == nil else {
                return;
            }
            oldDeviceId = deviceId;
        }
        didSet {
            guard oldValue != deviceId else {
                return;
            }
            updateDeviceId();
        }
    }
    
    open var enabled: Bool = false;
    open var pushServiceNode: String? {
        didSet {
            if let account = AccountManager.getAccount(forJid: context.sessionObject.userBareJid!.stringValue) {
                if pushServiceNode != account.pushServiceNode {
                    account.pushServiceNode = pushServiceNode;
                    AccountManager.updateAccount(account, notifyChange: false);
                }
            }
        }
    }
    
    open var isAvailablePushForAway: Bool {
        if let features: [String] = context.sessionObject.getProperty(DiscoveryModule.SERVER_FEATURES_KEY) {
            return features.contains(TigasePushNotificationsModule.PUSH_FOR_AWAY_XMLNS);
        }
        return false;
    }
    
    override open var context: Context! {
        willSet {
            if context != nil {
                context.eventBus.unregister(handler: self, for: SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
            }
        }
        didSet {
            if context != nil {
                context.eventBus.register(handler: self, for: SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
            }
        }
    }

    fileprivate let provider = "tigase:messenger:apns:1";
    
    public init(pushServiceJid: JID) {
        super.init();
        self.pushServiceJid = pushServiceJid;
    }
    
    open func registerDevice(onSuccess: @escaping ()-> Void, onError: @escaping (ErrorCondition?)->Void) {
        self.registerDevice(serviceJid: self.pushServiceJid!, provider: self.provider, deviceId: self.deviceId!, onSuccess: { (node) in
            self.pushServiceNode = node;
            self.enable(serviceJid: self.pushServiceJid!, node: node, enableForAway: AccountSettings.PushNotificationsForAway(self.context.sessionObject.userBareJid!.stringValue).getBool(), onSuccess: { (stanza) in
                onSuccess();
            }, onError: onError);
        }, onError: onError);
    }
    
    
    open func unregisterDevice(deviceId: String? = nil, onSuccess: @escaping () -> Void, onError: @escaping (ErrorCondition?) -> Void) {
        if let node = self.pushServiceNode {
            self.disable(serviceJid: self.pushServiceJid!, node: node, onSuccess: { (stanza) in
                self.pushServiceNode = nil;
                self.unregisterDevice(serviceJid: self.pushServiceJid!, provider: self.provider, deviceId: deviceId ?? self.deviceId!, onSuccess: onSuccess, onError: onError);
            }, onError: onError);
        } else {
            self.unregisterDevice(serviceJid: self.pushServiceJid!, provider: self.provider, deviceId: deviceId ?? self.deviceId!, onSuccess: onSuccess, onError: onError);
        }
    }
    
    open func handle(event: Event) {
        switch event {
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            updateDeviceId();
        default:
            break;
        }
    }
    
    func updateDeviceId() {
        if (context != nil) && (ResourceBinderModule.getBindedJid(context.sessionObject) != nil) {
            if (oldDeviceId != nil) {
                let removed = {
                    self.oldDeviceId = nil;
                    if (self.enabled && self.deviceId != nil) {
                        self.registerDevice();
                    }
                };
                self.unregisterDevice(deviceId: oldDeviceId, onSuccess: removed, onError: { (error) in
                    if error != nil && error == ErrorCondition.item_not_found {
                        removed();
                    }
                });
            }
            if deviceId != nil && pushServiceNode == nil && enabled {
                self.registerDevice();
            }
            if deviceId != nil && pushServiceNode != nil && !enabled {
                self.unregisterDevice(onSuccess: {
                    print("unregistered device", self.deviceId ?? "nil", "for push notifications");
                }, onError: { (error) in
                    print("unregistration failed", self.deviceId ?? "nil", "with error", error ?? "nil");
                })
            }
        }
    }
    
    func registerDevice() {
        self.registerDevice(onSuccess: {
            print("registered device", self.deviceId, "for push notifications at", self.pushServiceNode ?? "nil");
        }, onError: { (error) in
            let accountJid = self.context.sessionObject.userBareJid!.stringValue;
            if let account = AccountManager.getAccount(forJid: accountJid) {
                account.pushNotifications = false;
                self.enabled = false;
                AccountManager.updateAccount(account, notifyChange: false);
                
                let notification = UNMutableNotificationContent();
                notification.title = "Error";
                notification.userInfo = ["account": accountJid];
                notification.body = "Push Notifications for account \(accountJid) disabled due to error during registration in Push Notification servce: \(error)";
                notification.sound = UNNotificationSound.default();
                notification.categoryIdentifier = "ERROR";
                DispatchQueue.main.async {
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "push-notifications-" + accountJid, content: notification, trigger: nil));
                }
            }
        })
    }
    
    func findPushComponent(completionHandler: @escaping (JID?)->Void) {
        guard let discoModule: DiscoveryModule = context.modulesManager.getModule(DiscoveryModule.ID) else {
            completionHandler(nil);
            return;
        }
        discoModule.getItems(for: JID(context.sessionObject.userBareJid!.domain)!, node: nil, onItemsReceived: {(node, items) in
            let result = DiscoResults(items: items) { (jids) in
                print("found proper push components at", jids);
                completionHandler(jids.first);
            };
            items.forEach({ (item) in
                discoModule.getInfo(for: item.jid, node: item.node, onInfoReceived: { (node, identities, features) in
                    if identities.filter({ (identity) -> Bool in
                        identity.category == "pubsub" && identity.type == "push"
                    }).isEmpty || features.index(of: "urn:xmpp:push:0") == nil || features.index(of: "tigase:messenger:apns:1") == nil {
                        result.failure();
                    } else {
                        result.found(item.jid);
                    }
                }, onError: {(errorCondition) in
                    print("error:", errorCondition);
                    result.failure();
                });
            });
            result.checkFinished();
        }, onError: {(errorCondition) in
            print("error:", errorCondition);
            completionHandler(nil);
        });
    }
    
    private class DiscoResults {
        
        let items: [DiscoveryModule.Item];
        let completionHandler: (([JID])->Void);
        
        var responses = 0;
        var found: [JID] = [];
        
        init(items: [DiscoveryModule.Item], completionHandler: @escaping (([JID])->Void)) {
            self.items = items;
            self.completionHandler = completionHandler;
        }
        
        func found(_ jid: JID) {
            DispatchQueue.main.async {
                self.found.append(jid);
                self.responses += 1;
                self.checkFinished();
                
            }
        }
        
        func failure() {
            DispatchQueue.main.async {
                self.responses += 1;
                self.checkFinished();
            }
        }
        
        func checkFinished() {
            if (self.responses == items.count) {
                self.completionHandler(found);
            }
        }
        
    }
}
