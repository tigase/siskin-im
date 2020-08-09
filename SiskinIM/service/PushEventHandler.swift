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
    
    public static func unregisterDevice(from pushServiceJid: BareJID, account: BareJID, deviceId: String, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        guard let url = URL(string: "https://\(pushServiceJid.stringValue)/unregister-device/\(pushServiceJid.stringValue)") else {
            completionHandler(.failure(.service_unavailable));
            return;
        }
        var request = URLRequest(url: url);
        request.httpMethod = "POST";
        guard let payload = try? JSONEncoder().encode(UnregisterDeviceRequestPayload(account: account, provider: "tigase:messenger:apns:1", deviceToken: deviceId)) else {
            completionHandler(.failure(.internal_server_error));
            return;
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type");
        request.httpBody = payload;
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                completionHandler(.failure(.service_unavailable));
                return;
            }
            guard let data = data, let payload = try? JSONDecoder().decode(UnregisterDeviceResponsePayload.self, from: data) else {
                completionHandler(.failure(.internal_server_error));
                return;
            }
            if payload.success {
                completionHandler(.success(Void()));
            } else {
                completionHandler(.failure(.not_acceptable));
            }
        }
        task.resume();
    }
    
    public static let instance = PushEventHandler();

    var deviceId: String?;
    var pushkitDeviceId: String?;
    
    let events: [Event] = [DiscoveryModule.AccountFeaturesReceivedEvent.TYPE];
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(chatDestroyed(_:)), name: DBChatStore.CHAT_CLOSED, object: nil);
    }
    
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
        let hasPushJingle = features.contains(TigasePushNotificationsModule.Jingle.XMLNS);
        
        let pushkitDeviceId = hasPushJingle ? self.pushkitDeviceId : nil;
        
        if hasPush && pushModule.shouldEnable {
            if let pushSettings = pushModule.pushSettings {
                if pushSettings.deviceId != deviceId || pushSettings.pushkitDeviceId != pushkitDeviceId {
                    pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                        switch result {
                        case .success(_):
                            pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, completionHandler: { result2 in
                                print("reregistration:", result2);
                            });
                        case .failure(_):
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
                pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, completionHandler: { result in
                    print("automatic registration:", result);
                })
            }
        } else {
            if pushModule.pushSettings != nil, (!hasPush) || (!pushModule.shouldEnable) {
                pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                    print("automatic deregistration:", result);
                })
            }
        }
    }
    
    @objc func chatDestroyed(_ notification: Notification) {
        guard let c = notification.object as? DBChatProtocol else {
            return;
        }
        
        switch c {
        case is DBChat:
            // nothing to do for now...
            break;
        case let room as DBRoom:
            guard room.options.notifications != .none else {
                return;
            }
            self.updateAccountPushSettings(for: room.account);
        case let channel as DBChannel:
            guard channel.options.notifications != .none else {
                return;
            }
            self.updateAccountPushSettings(for: channel.account);
        default:
            break;
        }
    }
    
    func updateAccountPushSettings(for account: BareJID) {
        guard AccountSettings.pushHash(account).int() != 0 else {
            return;
        }
        if let client = XmppService.instance.getClient(for: account), client.state == .connected, let pushModule: SiskinPushNotificationsModule = client.modulesManager.getModule(SiskinPushNotificationsModule.ID), let pushSettings = pushModule.pushSettings {
            pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                print("updating account push settings finished", result);
            })
        } else {
            AccountSettings.pushHash(account).set(int: 0);
        }
    }
    
    public struct UnregisterDeviceRequestPayload: Encodable {
        var account: BareJID;
        var provider: String;
        var deviceToken: String;
        
        enum CodingKeys: String, CodingKey {
            case account
            case provider
            case deviceToken = "device-token"
        }
    }
    
    public struct UnregisterDeviceResponsePayload: Decodable {
        var success: Bool;
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self);
            success = try "success" == container.decode(String.self, forKey: .result);
        }
        
        enum CodingKeys: String, CodingKey {
            case result = "result";
        }
    }
}

