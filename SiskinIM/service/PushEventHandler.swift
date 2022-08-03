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
import Martin
import Combine
import TigaseLogging

open class PushEventHandler: XmppServiceExtension {
    
    static let instance = PushEventHandler();
    
    public static func unregisterDevice(from pushServiceJid: BareJID, account: BareJID, deviceId: String, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        unregisterDevice(from: pushServiceJid, path: "", account: account, deviceId: deviceId, completionHandler: { result in
            switch result {
            case .success(_):
                completionHandler(.success(Void()));
            case .failure(let error):
                if error == .internal_server_error || error == .service_unavailable {
                    self.unregisterDevice(from: pushServiceJid, path: "/rest/push", account: account, deviceId: deviceId, completionHandler: completionHandler);
                } else {
                    completionHandler(.failure(error));
                }
            }
        })
    }
    
    private static func unregisterDevice(from pushServiceJid: BareJID, path: String, account: BareJID, deviceId: String, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        guard let url = URL(string: "https://\(pushServiceJid.stringValue)\(path)/unregister-device/\(pushServiceJid.stringValue)") else {
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
    
    var deviceId: String?;
    var pushkitDeviceId: String?;
    
    private var cancellables: Set<AnyCancellable> = [];

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PushEventHandler");
    
    public func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        Settings.$enablePush.map({ $0 ?? false }).combineLatest(client.module(.disco).$accountDiscoResult).sink(receiveValue: { [weak client, weak self] enable, features in
            guard let client = client, client.state == .connected() else {
                return;
            }
            self?.updatePushRegistration(for: client, features: features.features, shouldEnable: enable);
        }).store(in: &cancellables);
    }

    
    init() {
        DBChatStore.instance.conversationsEventsPublisher.sink(receiveValue: { [weak self] event in
            switch event {
            case .destroyed(let conversation):
                self?.conversationDestroyed(conversation);
            case .created(let conversation):
                break;
            }
        }).store(in: &cancellables);
    }
            
    func updatePushRegistration(for client: XMPPClient, features: [String], shouldEnable: Bool) {
        guard let deviceId = self.deviceId else {
            return;
        }
        
        let pushModule = client.module(.push) as! SiskinPushNotificationsModule;
        let hasPush = features.contains(SiskinPushNotificationsModule.PUSH_NOTIFICATIONS_XMLNS);
        let hasPushJingle = features.contains(TigasePushNotificationsModule.Jingle.XMLNS);
        
        let pushkitDeviceId = hasPushJingle ? self.pushkitDeviceId : nil;
        
        if hasPush && shouldEnable {
            if let pushSettings = pushModule.pushSettings {
                if pushSettings.deviceId != deviceId || pushSettings.pushkitDeviceId != pushkitDeviceId {
                    pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                        switch result {
                        case .success(_):
                            pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, completionHandler: { result2 in
                                self.logger.debug("reregistration for account: \(client.userBareJid), result: \(result2)");
                            });
                        case .failure(_):
                            // we need to try again later
                            break;
                        }
                    });
                    return;
                } else if AccountSettings.pushHash(for: client.userBareJid) == 0 {
                    pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                        self.logger.debug("reenabling device for account: \(client.userBareJid), result: \(result)");
                    })
                }
            } else {
                pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, completionHandler: { result in
                    self.logger.debug("automatic registration for account: \(client.userBareJid), result: \(result)");
                })
            }
        } else {
            if pushModule.pushSettings != nil, (!hasPush) || (!shouldEnable) {
                pushModule.unregisterDeviceAndDisable(completionHandler: { result in
                    self.logger.debug("automatic deregistration for account: \(client.userBareJid), result: \(result)");
                })
            }
        }
    }
    
    private func conversationDestroyed(_ c: Conversation) {
        switch c {
        case is Chat:
            // nothing to do for now...
            break;
        case let room as Room:
            guard room.options.notifications != .none else {
                return;
            }
            DispatchQueue.global(qos: .background).async {
                self.updateAccountPushSettings(for: room.account);
            }
        case let channel as Channel:
            guard channel.options.notifications != .none else {
                return;
            }
            DispatchQueue.global(qos: .background).async {
                self.updateAccountPushSettings(for: channel.account);
            }
        default:
            break;
        }
    }
    
    func updateAccountPushSettings(for account: BareJID) {
        guard AccountSettings.pushHash(for: account) != 0 else {
            return;
        }
        if let client = XmppService.instance.getClient(for: account), client.state == .connected(), let pushModule = client.module(.push) as? SiskinPushNotificationsModule, let pushSettings = pushModule.pushSettings {
            pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                self.logger.debug("updating account push settings finished for account: \(client.userBareJid)");
            })
        } else {
            AccountSettings.pushHash(for: account, value: 0);
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

