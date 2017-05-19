//
//  TigasePushNotificationsModule.swift
//  Tigase-iOS-Messenger
//
//  Created by Andrzej Wójcik on 08.01.2017.
//  Copyright © 2017 Tigase, Inc. All rights reserved.
//

import UIKit
import TigaseSwift

open class TigasePushNotificationsModule: PushNotificationsModule, EventHandler {
    
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

    fileprivate let provider = "apns-binary-api";
    
    public init(pushServiceJid: JID) {
        super.init();
        self.pushServiceJid = pushServiceJid;
    }
    
    open func registerDevice(onSuccess: @escaping ()-> Void, onError: @escaping (ErrorCondition?)->Void) {
        self.registerDevice(serviceJid: self.pushServiceJid!, provider: self.provider, deviceId: self.deviceId!, onSuccess: { (node) in
            self.pushServiceNode = node;
            self.enable(serviceJid: self.pushServiceJid!, node: node, onSuccess: { (stanza) in
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
                    print("unregistered device", self.deviceId, "for push notifications");
                }, onError: { (error) in
                    print("unregistration failed", self.deviceId, "with error", error);
                })
            }
        }
    }
    
    func registerDevice() {
        self.registerDevice(onSuccess: {
            print("registered device", self.deviceId, "for push notifications at", self.pushServiceNode);
        }, onError: { (error) in
            let accountJid = self.context.sessionObject.userBareJid!.stringValue;
            if let account = AccountManager.getAccount(forJid: accountJid) {
                account.pushNotifications = false;
                self.enabled = false;
                AccountManager.updateAccount(account, notifyChange: false);
                
                let notification = UILocalNotification();
                notification.alertTitle = "Error";
                notification.alertAction = "fix";
                notification.userInfo = ["account": accountJid];
                notification.alertBody = "Push Notifications for account \(accountJid) disabled due to error during registration in Push Notification servce: \(error)";
                notification.soundName = UILocalNotificationDefaultSoundName;
                notification.category = "ERROR";
                DispatchQueue.main.async {
                    UIApplication.shared.presentLocalNotificationNow(notification);
                }
            }
        })
    }
}
