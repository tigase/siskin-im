//
// Settings.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import Martin
import Combine
import Shared

@propertyWrapper class UserDefaultsSetting<Value> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value,Never>;
        
    var projectedValue: AnyPublisher<Value,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value = storage.value(forKey: key) as? Value ?? defaultValue;
        self.value = CurrentValueSubject<Value,Never>(value);
    }
}

@propertyWrapper class UserDefaultsRawSetting<Value: RawRepresentable> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value,Never>;
        
    var projectedValue: AnyPublisher<Value,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value = storage.value(forKey: key) ?? defaultValue;
        self.value = CurrentValueSubject<Value,Never>(value);
    }
}

extension UserDefaultsSetting where Value: ExpressibleByNilLiteral {
    convenience init(key: String, storage: UserDefaults = .standard) {
        self.init(key: key, defaultValue: nil, storage: storage);
    }
}

extension UserDefaults {

    func value<T: RawRepresentable>(forKey key: String) -> T? {
        guard let value = value(forKey: key) as? T.RawValue else {
            return nil;
        }
        return T(rawValue: value);
    }
    
    func setValue<T: RawRepresentable>(_ value: T?, forKey key: String) {
        set(value?.rawValue, forKey: key);
    }
}

@propertyWrapper class UserDefaultsOptionalRawSetting<Value: RawRepresentable> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value?,Never>;
        
    var projectedValue: AnyPublisher<Value?,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value? {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    init(key: String, defaultValue: Value?, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value? = storage.value(forKey: key) ?? defaultValue;
        self.value = CurrentValueSubject<Value?,Never>(value);
    }
}

class SettingsStore {
    @UserDefaultsSetting(key: "defaultAccount")
    var defaultAccount: String?;
    @UserDefaultsOptionalRawSetting(key: "StatusType", defaultValue: nil)
    var statusType: Presence.Show?;
    @UserDefaultsSetting(key: "StatusMessage")
    var statusMessage: String?;
    @UserDefaultsRawSetting(key: "RosterType", defaultValue: .flat)
    var rosterType: RosterType;
    @UserDefaultsRawSetting(key: "RosterItemsOrder", defaultValue: .alphabetical)
    var rosterItemsOrder: RosterSortingOrder;
    @UserDefaultsSetting(key: "RosterAvailableOnly", defaultValue: false)
    var rosterAvailableOnly: Bool;
    @UserDefaultsSetting(key: "RosterDisplayHiddenGroup", defaultValue: false)
    var rosterDisplayHiddenGroup: Bool;
    @UserDefaultsSetting(key: "AutoSubscribeOnAcceptedSubscriptionRequest", defaultValue: true)
    var autoSubscribeOnAcceptedSubscriptionRequest: Bool;
    @UserDefaultsSetting(key: "NotificationsFromUnknown", defaultValue: true)
    var notificationsFromUnknown: Bool;
    @UserDefaultsSetting(key: "RecentsMessageLinesNo", defaultValue: 2)
    var recentsMessageLinesNo: Int;
    @UserDefaultsSetting(key: "SharingViaHttpUpload", defaultValue: false)
    var sharingViaHttpUpload: Bool;
    @UserDefaultsSetting(key: "fileDownloadSizeLimit", defaultValue: 4)
    var fileDownloadSizeLimit: Int;
    @UserDefaultsSetting(key: "confirmMessages", defaultValue: true)
    var confirmMessages: Bool;
    @UserDefaultsSetting(key: "SendMessageOnReturn", defaultValue: true)
    var sendMessageOnReturn: Bool;
    @UserDefaultsSetting(key: "CopyMessagesWithTimestamps", defaultValue: false)
    var copyMessagesWithTimestamps: Bool;
    @UserDefaultsSetting(key: "XmppPipelining", defaultValue: false)
    var xmppPipelining: Bool;
    
    @UserDefaultsSetting(key: "enableBookmarksSync", defaultValue: true)
    var enableBookmarksSync: Bool;
    @UserDefaultsRawSetting(key: "messageEncryption", defaultValue: ConversationEncryption.none)
    var messageEncryption: ConversationEncryption;
    @UserDefaultsSetting(key: "markdown", defaultValue: true)
    var enableMarkdownFormatting: Bool;
    @UserDefaultsSetting(key: "ShowEmoticons", defaultValue: false)
    var showEmoticons: Bool;
    
    @UserDefaultsSetting(key: "linkPreviews", defaultValue: true)
    var linkPreviews: Bool;
    @UserDefaultsRawSetting(key: "appearance", defaultValue: .auto)
    var appearance: Appearance
    @UserDefaultsSetting(key: "usePublicStunServers", defaultValue: true)
    var usePublicStunServers: Bool;
    
    @UserDefaultsRawSetting(key: "imageQuality", defaultValue: .medium)
    var imageQuality: ImageQuality
    @UserDefaultsRawSetting(key: "videoQuality", defaultValue: .medium)
    var videoQuality: VideoQuality

    @UserDefaultsSetting(key: "enablePush", defaultValue: nil)
    var enablePush: Bool?;
    
    public static let sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share")!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    fileprivate init() {
        $sharingViaHttpUpload.sink(receiveValue: { value in
            SettingsStore.sharedDefaults.setValue(value, forKey: "SharingViaHttpUpload");
        }).store(in: &cancellables);
        $imageQuality.sink(receiveValue: { value in
            SettingsStore.sharedDefaults.setValue(value.rawValue, forKey: "imageQuality");
        }).store(in: &cancellables);
        $videoQuality.sink(receiveValue: { value in
            SettingsStore.sharedDefaults.setValue(value.rawValue, forKey: "videoQuality");
        }).store(in: &cancellables);
    }
    
    public static func initialize() {
        UserDefaults.standard.removeObject(forKey: "DeleteChatHistoryOnClose");
        UserDefaults.standard.removeObject(forKey: "enableMessageCarbons");
        UserDefaults.standard.removeObject(forKey: "DeviceToken");
        UserDefaults.standard.removeObject(forKey: "RecentsOrder");
        UserDefaults.standard.removeObject(forKey: "AppearanceTheme");
        
        if UserDefaults.standard.value(forKey: "confirmMessages") == nil {
            if let value = UserDefaults.standard.value(forKey: "MessageDeliveryReceiptsEnabled") as? Bool {
                UserDefaults.standard.setValue(value, forKey: "confirmMessages");
                UserDefaults.standard.removeObject(forKey: "MessageDeliveryReceiptsEnabled");
            }
        }
        
        DispatchQueue.global(qos: .background).async {
            let removeOlder = Date().addingTimeInterval(7 * 24 * 60 * 60 * (-1.0));
            for (k,v) in SettingsStore.sharedDefaults.dictionaryRepresentation() {
                if k.starts(with: "upload-") {
                    let hash = k.replacingOccurrences(of: "upload-", with: "");
                    if let timestamp = (v as? [String: Any])?["timestamp"] as? Date {
                        if timestamp < removeOlder {
                            SettingsStore.sharedDefaults.removeObject(forKey: k);
                            let localUploadDirUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("upload", isDirectory: true).appendingPathComponent(hash, isDirectory: false);
                            if FileManager.default.fileExists(atPath: localUploadDirUrl.path) {
                                try? FileManager.default.removeItem(at: localUploadDirUrl);
                            }
                        }
                    } else {
                        SettingsStore.sharedDefaults.removeObject(forKey: k);
                        let localUploadDirUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("upload", isDirectory: true).appendingPathComponent(hash, isDirectory: false);
                        if FileManager.default.fileExists(atPath: localUploadDirUrl.path) {
                            try? FileManager.default.removeItem(at: localUploadDirUrl);
                        }
                    }
                }
            }
        }
        
        let suffixesToRemove = ["MessageSyncAutomatic", "MessageSyncPeriod", "MessageSyncTime"];
        
        let keysToRemove = UserDefaults.standard.dictionaryRepresentation().keys.filter({ key in
            for suffix in suffixesToRemove {
                if suffix.hasSuffix(".\(suffix)") {
                    return true;
                }
            }
            return false;
        });
        
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key);
        }
    }
}

let Settings: SettingsStore = {
    SettingsStore.initialize();
    return SettingsStore();
}();

enum Appearance: String, CustomStringConvertible {
    case auto
    case light
    case dark
    
    var description: String {
        switch self {
        case .auto:
            return NSLocalizedString("Auto", comment: "appearance type")
        case .light:
            return NSLocalizedString("Light", comment: "appearance type")
        case .dark:
            return NSLocalizedString("Dark", comment: "appearance type")
        }
    }
    
    var value: UIUserInterfaceStyle {
        switch self {
        case .auto:
            return .unspecified;
        case .light:
            return .light;
        case .dark:
            return .dark;
        }
    }
}

public struct AccountSettingsStore {
    
    enum Key: String {
        case PushNotificationsForAway
        case LastError
        case knownServerFeatures = "KnownServerFeatures"
        case omemoRegistrationId
        case reconnectionLocation
        case pushHash
    }
    
    var storage: UserDefaults = .standard;
    
    func pushNotificationsForAway(for account: BareJID) -> Bool {
        return value(for: account, key: .PushNotificationsForAway) ?? false;
    }
    
    func pushNotificationsForAway(for account: BareJID, value: Bool) {
        self.value(for: account, key: .PushNotificationsForAway, value: value);
    }
    
    func lastError(for account: BareJID) -> String? {
        return value(for: account, key: .LastError);
    }
    
    func lastError(for account: BareJID, value: String?) {
        self.value(for: account, key: .LastError, value: value);
    }
    
    func knownServerFeatures(for account: BareJID) -> [ServerFeature] {
        guard let features: [String] = value(for: account, key: .knownServerFeatures) else {
            return [];
        }
        let serverFeatures = features.compactMap({ ServerFeature(rawValue: $0) });
        if serverFeatures.count == 0 && !features.isEmpty {
            // if this does not match, we may have features in old format..
            var updateFeatures = ServerFeature.from(features: features);
            updateFeatures.removeAll(where: { $0 == .push });
            knownServerFeatures(for: account, value: updateFeatures);
            return updateFeatures;
        }
        return serverFeatures;
    }
    
    func knownServerFeatures(for account: BareJID, value: [ServerFeature]) {
        self.value(for: account, key: .knownServerFeatures, value: value.map({ $0.rawValue }));
    }
    
    func omemoRegistrationId(for account: BareJID) -> UInt32? {
        guard let value: String = self.value(for: account, key: .omemoRegistrationId) else {
            return nil;
        }
        return UInt32(value);
    }
    
    func omemoRegistrationId(for account: BareJID, value: UInt32?) {
        self.value(for: account, key: .omemoRegistrationId, value: value == nil ? nil : String(value!));
    }
    
    func reconnectionLocation(for account: BareJID) -> ConnectorEndpoint? {
        guard let string: String = value(for: account, key: .reconnectionLocation) else {
            return nil;
        }
        return try? JSONDecoder().decode(SocketConnectorNetwork.Endpoint.self, from: Data(base64Encoded: string)!);
    }
    
    func reconnectionLocation(for account: BareJID, value: ConnectorEndpoint?) {
        let endpoint = value as? SocketConnectorNetwork.Endpoint;
        let data = try? JSONEncoder().encode(endpoint);
        self.value(for: account, key: .reconnectionLocation, value: data?.base64EncodedString());
    }

    func pushHash(for account: BareJID) -> Int {
        return value(for: account, key: .pushHash) ?? 0;
    }
    
    func pushHash(for account: BareJID, value: Int) {
        self.value(for: account, key: .pushHash, value: value);
    }
    
    func value<V>(for account: BareJID, key: Key) -> V? {
        return storage.value(forKey: self.key(for: account, key: key)) as? V;
    }
    
    func value<V>(for account: BareJID, key: Key, value: V?) {
        storage.setValue(value, forKey: self.key(for: account, key: key));
    }
    
    private func key(for account: BareJID, key: Key) -> String {
        return "accounts.\(account).\(key.rawValue)";
    }
    
    public func initialize() {
        let accounts = AccountManager.getAccounts();
        let toRemove = storage.dictionaryRepresentation().keys.filter { (key) -> Bool in
            return key.hasPrefix("accounts.") && accounts.firstIndex(where: { (account) -> Bool in
                return key.hasPrefix("accounts.\(account.stringValue).");
            }) == nil;
        };
        toRemove.forEach { (key) in
            storage.removeObject(forKey: key);
        }
    }

}

let AccountSettings = AccountSettingsStore();
