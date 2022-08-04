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
    
    public static func unregisterDevice(from pushServiceJid: BareJID, account: BareJID, deviceId: String) async throws {
        do {
            try await unregisterDevice(from: pushServiceJid, path: "", account: account, deviceId: deviceId);
        } catch let error as XMPPError {
            switch error.condition {
            case .internal_server_error, .service_unavailable:
                try await unregisterDevice(from: pushServiceJid, path: "/rest/push", account: account, deviceId: deviceId);
            default:
                throw error;
            }
        }
    }
    
    private static func unregisterDevice(from pushServiceJid: BareJID, path: String, account: BareJID, deviceId: String) async throws {
        guard let url = URL(string: "https://\(pushServiceJid.description)\(path)/unregister-device/\(pushServiceJid.description)") else {
            throw XMPPError(condition: .service_unavailable);
        }
        var request = URLRequest(url: url);
        request.httpMethod = "POST";
        guard let payload = try? JSONEncoder().encode(UnregisterDeviceRequestPayload(account: account, provider: "tigase:messenger:apns:1", deviceToken: deviceId)) else {
            throw XMPPError(condition: .internal_server_error);
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type");
        request.httpBody = payload;
        
        return try await withUnsafeThrowingContinuation({ continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard error == nil else {
                    continuation.resume(throwing: XMPPError(condition: .service_unavailable));
                    return;
                }
                guard let data = data, let payload = try? JSONDecoder().decode(UnregisterDeviceResponsePayload.self, from: data) else {
                    continuation.resume(throwing: XMPPError(condition: .internal_server_error));
                    return;
                }
                if payload.success {
                    continuation.resume(returning: Void())
                } else {
                    continuation.resume(throwing: XMPPError(condition: .not_acceptable));
                }
            }
            task.resume();
        })
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
        
        Task {
            do {
            if hasPush && shouldEnable {
                if let pushSettings = pushModule.pushSettings {
                    if pushSettings.deviceId != deviceId || pushSettings.pushkitDeviceId != pushkitDeviceId {
                        self.logger.debug("reregistration for account: \(client.userBareJid)")
                        try await pushModule.unregisterDeviceAndDisable();
                        _ = try await pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId);
                    } else if AccountSettings.pushHash(for: client.userBareJid) == 0 {
                        self.logger.debug("reenabling device for account: \(client.userBareJid)")
                        try await pushModule.reenable(pushSettings: pushSettings);
                    }
                } else {
                    self.logger.debug("automatic registration for account: \(client.userBareJid)")
                    _ = try await pushModule.registerDeviceAndEnable(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId);
                }
            } else {
                if pushModule.pushSettings != nil, (!hasPush) || (!shouldEnable) {
                    self.logger.debug("automatic deregistration for account: \(client.userBareJid)");
                    try await pushModule.unregisterDeviceAndDisable();
                }
            }
            } catch {
                self.logger.debug("changing push registration for account \(client.userBareJid) failed: \(error)")
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
            Task {
                self.logger.debug("updating account push settings finished for account: \(client.userBareJid)");
                try await pushModule.reenable(pushSettings: pushSettings)
            }
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

