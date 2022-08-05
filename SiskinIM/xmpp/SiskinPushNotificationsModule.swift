//
// SiskinPushNotificationsModule.swift
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

import UIKit
import Foundation
import UserNotifications
import CryptoKit
import Shared
import Martin

public struct PushSettings: Codable, Equatable, Sendable {
    public var registration: SiskinPushNotificationsModule.PushRegistration?;
    public var enableForAway: Bool;
    
    public init() {
        registration = nil;
        enableForAway = false;
    }
    
}


open class SiskinPushNotificationsModule: TigasePushNotificationsModule {

    public struct PushSettingsOld: Codable, Equatable, Sendable {
                
        public let jid: JID;
        public let node: String;
        public let deviceId: String;
        public let pushkitDeviceId: String?;
        public let encryption: Bool;
        public let maxSize: Int?;

        init?(dictionary: [String: Any]?) {
            guard let dict = dictionary else {
                return nil;
            }
            guard let jid = JID(dict["jid"] as? String), let node = dict["node"] as? String, let deviceId = dict["device"] as? String else {
                return nil;
            }
            self.init(jid: jid, node: node, deviceId: deviceId, pushkitDeviceId: dict["pushkitDevice"] as? String, encryption: dict["encryption"] as? Bool ?? false, maxSize: dict["maxSize"] as? Int);
        }
        
        init(jid: JID, node: String, deviceId: String, pushkitDeviceId: String? = nil, encryption: Bool, maxSize: Int?) {
            self.jid = jid;
            self.node = node;
            self.deviceId = deviceId;
            self.pushkitDeviceId = pushkitDeviceId;
            self.encryption = encryption;
            self.maxSize = maxSize;
        }
        
        func dictionary() -> [String: Any] {
            var dict: [String: Any] =  ["jid": jid.description, "node": node, "device": deviceId];
            if let pushkitDevice = self.pushkitDeviceId {
                dict["pushkitDevice"] = pushkitDevice;
            }
            if encryption {
                dict["encryption"] = true;
            }
            if maxSize != nil {
                dict["maxSize"] = maxSize;
            }
            return dict;
        }
        
    }
        
    public struct PushRegistration: Codable, Equatable, Sendable {
                        
        public let jid: JID;
        public let node: String;
        public let deviceId: String;
        public let pushkitDeviceId: String?;
        
        init(jid: JID, node: String, deviceId: String, pushkitDeviceId: String? = nil) {
            self.jid = jid;
            self.node = node;
            self.deviceId = deviceId;
            self.pushkitDeviceId = pushkitDeviceId;
        }
        
    }
        
    public let defaultPushServiceJid: JID;

    fileprivate let providerId = "tigase:messenger:apns:1";
    fileprivate let provider: SiskinPushNotificationsModuleProviderProtocol;
    
    public init(defaultPushServiceJid: JID, provider: SiskinPushNotificationsModuleProviderProtocol) {
        self.defaultPushServiceJid = defaultPushServiceJid;
        self.provider = provider;
        super.init();
    }
    
    open func registerDevice(deviceId: String, pushkitDeviceId: String?) async throws -> PushRegistration {
        do {
            let jid = try await self.findPushComponent();
            return try await self.registerDevice(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, pushServiceJid: jid);
        } catch {
            return try await self.registerDevice(deviceId: deviceId, pushkitDeviceId: pushkitDeviceId, pushServiceJid: self.defaultPushServiceJid);
        }
    }
    
    private func prepareExtensions(for context: Context, settings: PushSettings, componentSupportsEncryption: Bool, maxSize: Int?) -> [PushNotificationsModuleExtension] {
        var extensions: [PushNotificationsModuleExtension] = [];
        
        if !Settings.notificationsFromUnknown {
            if self.isSupported(extension: TigasePushNotificationsModule.IgnoreUnknown.self) {
                extensions.append(TigasePushNotificationsModule.IgnoreUnknown());
            }
        }
        
        let account = context.userBareJid;
        
        let groupchatFilter = self.isSupported(extension: TigasePushNotificationsModule.GroupchatFilter.self);
        if groupchatFilter {
            extensions.append(TigasePushNotificationsModule.GroupchatFilter(rules: provider.groupchatFilterRules(for: context)));
        }
        let muted = self.isSupported(extension: TigasePushNotificationsModule.Muted.self)
        if muted {
            extensions.append(TigasePushNotificationsModule.Muted(jids: provider.mutedChats(for: context)));
        }
                
        if muted && groupchatFilter {
            let priority = self.isSupported(extension: TigasePushNotificationsModule.Priority.self);
            if priority {
                extensions.append(TigasePushNotificationsModule.Priority());
                if componentSupportsEncryption && self.isSupported(extension: TigasePushNotificationsModule.Encryption.self) && self.isSupported(feature: TigasePushNotificationsModule.Encryption.AES_128_GCM) {
                    extensions.append(TigasePushNotificationsModule.Encryption(algorithm: TigasePushNotificationsModule.Encryption.AES_128_GCM.replacingOccurrences(of: "tigase:push:encrypt:", with: ""), key: NotificationEncryptionKeys.key(for: account) ?? SymmetricKey(size: .bits128).data(), maxPayloadSize: maxSize));
                }
            }
        }
        
        if settings.enableForAway {
            extensions.append(TigasePushNotificationsModule.PushForAway());
        }
        
        if self.isSupported(extension: TigasePushNotificationsModule.Jingle.self) {
            extensions.append(TigasePushNotificationsModule.Jingle());
        }
        
        return extensions;
    }
    
    open func registerDevice(deviceId: String, pushkitDeviceId: String? = nil, pushServiceJid: JID) async throws -> PushRegistration {
        let data = try await self.registerDevice(serviceJid: pushServiceJid, provider: self.providerId, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId);
        return PushRegistration(jid: pushServiceJid, node: data.node, deviceId: deviceId, pushkitDeviceId: pushkitDeviceId);
    }
    
    open func enable(settings: PushSettings, publishOptions: PubSubSubscribeOptions? = nil) async throws {
        guard let context = self.context else {
            throw XMPPError(condition: .remote_server_timeout);
        }
        guard let registration = settings.registration else {
            throw XMPPError(condition: .bad_request);
        }
        
        let extensions: [PushNotificationsModuleExtension] = self.prepareExtensions(for: context, settings: settings, componentSupportsEncryption: true, maxSize: 3072);
                
        let encryption = extensions.first(where: { ext in
            return ext is TigasePushNotificationsModule.Encryption;
        }) as? TigasePushNotificationsModule.Encryption;
                
        do {
            _ = try await self.enable(serviceJid: registration.jid, node: registration.node, extensions: extensions);
            let accountJid = context.userBareJid;
            NotificationEncryptionKeys.set(key: encryption?.key, for: accountJid);
        } catch {
            do {
                try await self.unregisterDevice(serviceJid: registration.jid, provider: self.providerId, deviceId: registration.deviceId);
            } catch {}
            throw error;
        }
    }
        
    public func unregisterDeviceAndDisable(registration: PushRegistration) async throws {
        if let context = self.context {
            try await withThrowingTaskGroup(of: Void.self, returning: Void.self, body: { group in
                group.addTask {
                    do {
                        _ = try await self.disable(serviceJid: registration.jid, node: registration.node);
                    } catch let error as XMPPError {
                        guard error.condition == .item_not_found else {
                            throw error;
                        }
                    }
                }
                group.addTask {
                    do {
                        try await self.unregisterDevice(serviceJid: registration.jid, provider: self.providerId, deviceId: registration.deviceId);
                    } catch let error as XMPPError {
                        guard error.condition == .item_not_found else {
                            throw error;
                        }
                    }
                }
                for try await _ in group {
                }
            })
        } else {
            throw XMPPError(condition: .remote_server_not_found);
        }
    }
    
    func findPushComponent() async throws -> JID {
        let jids = try await findPushComponents(requiredFeatures: ["urn:xmpp:push:0", self.providerId]);
        guard let jid = jids.first else {
            throw XMPPError(condition: .feature_not_implemented);
        }
        return jid;
    }
    
}

public protocol SiskinPushNotificationsModuleProviderProtocol {
    
    func mutedChats(for context: Context) -> [BareJID];
    
    func groupchatFilterRules(for context: Context) -> [TigasePushNotificationsModule.GroupchatFilter.Rule];
    
}
