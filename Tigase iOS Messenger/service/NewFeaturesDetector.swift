//
// NewFeaturesDetector.swift
//
// Tigase iOS Messenger
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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

class NewFeaturesDetector: EventHandler {
    
    let suggestions: [NewFeaturesDetectorSuggestion] = [MAMSuggestion(), PushSuggestion()];
    weak var xmppService: XmppService?;
    
    func handle(event: Event) {
        switch event {
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let xmppService = self.xmppService else {
                return;
            }
            guard DispatchQueue.main.sync(execute: { return UIApplication.shared.applicationState == .active }) else {
                return;
            }

            let knownFeatures = AccountSettings.KnownServerFeatures(account.stringValue).getStrings() ?? [];
            let newFeatures = e.features.filter { (feature) -> Bool in
                return !knownFeatures.contains(feature);
            };
            
            suggestions.forEach { suggestion in
                suggestion.handle(xmppService: xmppService, account: account, newServerFeatures: newFeatures);
            }
            
            let newKnownFeatures = e.features.filter { feature -> Bool in
                return suggestions.contains(where: { (suggestion) -> Bool in
                    return suggestion.isCapable(feature);
                })
            }
            
            AccountSettings.KnownServerFeatures(account.stringValue).set(strings: newKnownFeatures);
            
            break;
        default:
            break;
        }
    }
    
    class MAMSuggestion: NewFeaturesDetectorSuggestion {
        
        let feature = MessageArchiveManagementModule.MAM_XMLNS;
        
        func isCapable(_ feature: String) -> Bool {
            return self.feature == feature;
        }

        func handle(xmppService: XmppService, account: BareJID, newServerFeatures features: [String]) {
            guard features.contains(feature) else {
                return;
            }
            
            askToEnableMAM(xmppService: xmppService, account: account);
        }
     
        fileprivate func askToEnableMAM(xmppService: XmppService, account: BareJID) {
            guard let mamModule: MessageArchiveManagementModule = xmppService.getClient(forJid: account)?.modulesManager.getModule(MessageArchiveManagementModule.ID) else {
                return;
            }
            
            mamModule.retrieveSettings(onSuccess: { (defValue, always, never) in
                if defValue == .never {
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Message Archiving", message: "Your server for account \(account) supports message archiving. Would you like to enable this feature?", preferredStyle: UIAlertController.Style.alert);
                        
                        alert.addAction(UIAlertAction(title: "Enable", style: .default, handler: { (action) in
                            mamModule.updateSettings(defaultValue: .always, always: always, never: never, onSuccess: { (defValue, always, never) in
                                self.askToEnableMessageSync(xmppService: xmppService, account: account);
                            }, onError: { (error, stanza) in
                                self.showError(title: "Message Archiving Error", message: "Server \(account.domain) returned an error on the request to enable archiving. You can try to enable this feature later on from the account settings.");
                            });
                        }))
                        alert.addAction(UIAlertAction(title: "Not now", style: .cancel, handler: nil));
                        
                        UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil);
                    }
                } else {
                    self.askToEnableMessageSync(xmppService: xmppService, account: account);
                }
            }, onError: { (error, stanza) in
                print("received an error:", error as Any, "- ignoring");
            });
        }
        
        fileprivate func askToEnableMessageSync(xmppService: XmppService, account: BareJID) {
            guard !AccountSettings.MessageSyncAutomatic(account.stringValue).getBool() else {
                return;
            }
            
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Message Synchronization", message: "Would you like to have synchronized copy of your messages exchanged using \(account.domain) from the last week kept on this device?", preferredStyle: UIAlertController.Style.alert);
                
                alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action) in
                    AccountSettings.MessageSyncPeriod(account.stringValue).set(double: 24 * 7);
                    AccountSettings.MessageSyncAutomatic(account.stringValue).set(bool: true);
                    
                    xmppService.syncMessages(for: account);
                }))
                alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                
                UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil);
            }
        }
    }
    
    class PushSuggestion: NewFeaturesDetectorSuggestion {
        
        let feature = PushNotificationsModule.PUSH_NOTIFICATIONS_XMLNS;
        
        func isCapable(_ feature: String) -> Bool {
            return self.feature == feature;
        }
        
        func handle(xmppService: XmppService, account: BareJID, newServerFeatures features: [String]) {
            guard features.contains(feature) else {
                return;
            }
            
            guard let pushModule: TigasePushNotificationsModule = xmppService.getClient(forJid: account)?.modulesManager.getModule(TigasePushNotificationsModule.ID), pushModule.deviceId != nil else {
                return;
            }
            
            guard !(AccountManager.getAccount(forJid: account.stringValue)?.pushNotifications ?? true) else {
                return;
            }
            
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Push Notifications", message: "Your server for account \(account) supports push notifications. With this feature enabled Tigase iOS Messenger can be automatically notified about new messages when it is in background or stopped.\nIf enabled, notifications about new messages will be forwarded to our push component and delivered to the device. These notifications will contain message senders jid and part of a message.\nDo you want to enable push notifications?", preferredStyle: UIAlertController.Style.alert);
                
                alert.addAction(UIAlertAction(title: "Enable", style: .default, handler: { (action) in
                    self.enablePush(xmppService: xmppService, account: account);
                }))
                alert.addAction(UIAlertAction(title: "Not now", style: .cancel, handler: nil));
                
                UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil);
            }
        }
        
        func enablePush(xmppService: XmppService, account accountJid: BareJID) {
            guard let pushModule: TigasePushNotificationsModule = xmppService.getClient(forJid: accountJid)?.modulesManager.getModule(TigasePushNotificationsModule.ID) else {
                return;
            }
            
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
                    self.showError(title: "Push Notifications Error", message: "Server \(accountJid.domain) returned an error on the request to enable push notifications. You can try to enable this feature later on from the account settings.");
                })
            });

        }
        
    }
}

protocol NewFeaturesDetectorSuggestion: class {
    
    func handle(xmppService: XmppService, account: BareJID, newServerFeatures features: [String]);
    
    func isCapable(_ feature: String) -> Bool;
    
}

extension NewFeaturesDetectorSuggestion {
    
    func showError(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert);
            
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            
            UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil);
        }
    }
    
}
