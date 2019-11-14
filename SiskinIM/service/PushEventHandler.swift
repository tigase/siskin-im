//
// PushEventHandler.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

open class PushEventHandler: XmppServiceEventHandler {
    
    public static let instance = PushEventHandler();

    var deviceId: String?;
    
    let events: [Event] = [DiscoveryModule.AccountFeaturesReceivedEvent.TYPE];
    
    public func handle(event: Event) {
        switch event {
        case let e as DiscoveryModule.AccountFeaturesReceivedEvent:
            updatePushRegistration(for: e.sessionObject.userBareJid!, features: e.features);
        default:
            break;
        }
    }
    
    func updatePushRegistration(for account: BareJID, features: [String]) {
        guard let client = XmppService.instance.getClient(for: account), let pushModule: SiskinPushNotificationsModule = client.modulesManager.getModule(SiskinPushNotificationsModule.ID), let deviceId = self.deviceId else {
            return;
        }
        
        let hasPush = features.contains(SiskinPushNotificationsModule.PUSH_NOTIFICATIONS_XMLNS);
        
        if hasPush && pushModule.shouldEnable {
            if let pushSettings = pushModule.pushSettings {
                if pushSettings.deviceId != deviceId {
                    pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                        switch result {
                        case .success(_):
                            pushModule.registerDeviceAndEnable(deviceId: deviceId, completionHandler: { result2 in
                                print("reregistration:", result2);
                            });
                        case .failure(let err):
                            // we need to try again later
                            break;
                        }
                    });
                    return;
                } else if AccountSettings.pushHash(account).int() == 0 {
                    pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                        print("reenabling device:", result);
                    })
                }
            } else {
                pushModule.registerDeviceAndEnable(deviceId: deviceId, completionHandler: { result in
                    print("automatic registration:", result);
                })
            }
        } else {
            if let pushSettings = pushModule.pushSettings, (!hasPush) || (!pushModule.shouldEnable) {
                pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                    print("automatic deregistration:", result);
                })
            }
        }
    }
    
    
}

