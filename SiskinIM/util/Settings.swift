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

import Foundation
import TigaseSwift

public enum Settings: String {
    case DeleteChatHistoryOnChatClose
    case enableMessageCarbons;
    case StatusType
    case StatusMessage
    case RosterType
    case RosterItemsOrder
    case RosterAvailableOnly
    case RosterDisplayHiddenGroup
    case AutoSubscribeOnAcceptedSubscriptionRequest
    @available(swift, deprecated: 1.0)
    case DeviceToken
    case NotificationsFromUnknown
    case RecentsMessageLinesNo
    case RecentsOrder
    case SharingViaHttpUpload
    //case MaxImagePreviewSize
    case fileDownloadSizeLimit
    case MessageDeliveryReceiptsEnabled
    //case SimplifiedLinkToFileIfPreviewIsAvailable
    case SendMessageOnReturn
    case CopyMessagesWithTimestamps
    case XmppPipelining
    case AppearanceTheme
    case enableBookmarksSync
    case messageEncryption
    case EnableMarkdownFormatting = "markdown"
    case ShowEmoticons
    
    @available(iOS 13.0, *)
    case linkPreviews
    case appearance
    
    public static let SETTINGS_CHANGED = Notification.Name("settingsChanged");
    
    fileprivate static var store: UserDefaults {
        return UserDefaults.standard;
    }
    
    public static let sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share");
    
    public static func initialize() {
        let defaults: [String: Any] = [
            "DeleteChatHistoryOnChatClose" : false,
            "enableMessageCarbons" : true,
            "RosterType" : "flat",
            "RosterItemsOrder" : RosterSortingOrder.alphabetical.rawValue,
            "RosterAvailableOnly" : false,
            "RosterDisplayHiddenGroup" : false,
            "AutoSubscribeOnAcceptedSubscriptionRequest" : false,
            "NotificationsFromUnknown" : true,
            "RecentsMessageLinesNo" : 2,
            "RecentsOrder" : "byTime",
            "SendMessageOnReturn" : true,
            "messageEncryption": "none",
            "linkPreviews": true,
            "appearance": "auto"
        ];
        store.register(defaults: defaults);
        ["EnableMessageCarbons": Settings.enableMessageCarbons, "MessageEncryption": .messageEncryption, "EnableBookmarksSync": Settings.enableBookmarksSync].forEach { (oldKey, newKey) in
            if let val = store.object(forKey: oldKey) {
                store.removeObject(forKey: oldKey);
                store.set(val, forKey: newKey.rawValue)
            }
        }
        if store.object(forKey: "MaxImagePreviewSize") != nil {
            let downloadLimit = store.integer(forKey: "MaxImagePreviewSize");
            store.removeObject(forKey: "MaxImagePreviewSize");
            Settings.fileDownloadSizeLimit.setValue(downloadLimit);
        }
        store.removeObject(forKey: "new-ui");
        if let val = store.object(forKey: "AppearanceTheme") as? String {
            store.removeObject(forKey: "AppearanceTheme");
            let parts = val.split(separator: "-");
            if parts.count > 1 {
                switch parts[1] {
                case "light":
                    store.set("light", forKey: Settings.appearance.rawValue);
                case "dark":
                    store.set("dark", forKey: Settings.appearance.rawValue);
                default:
                    break;
                }
            }
        }
        store.dictionaryRepresentation().forEach { (k, v) in
            if let key = Settings(rawValue: k) {
                if isShared(key: key) {
                    sharedDefaults!.set(v, forKey: key.rawValue);
                }
            }
        }
        DispatchQueue.global(qos: .background).async {
            let removeOlder = Date().addingTimeInterval(7 * 24 * 60 * 60 * (-1.0));
            for (k,v) in self.sharedDefaults!.dictionaryRepresentation() {
                if k.starts(with: "upload-") {
                    let hash = k.replacingOccurrences(of: "upload-", with: "");
                    if let timestamp = (v as? [String: Any])?["timestamp"] as? Date {
                        if timestamp < removeOlder {
                            self.sharedDefaults?.removeObject(forKey: k);
                            let localUploadDirUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("upload", isDirectory: true).appendingPathComponent(hash, isDirectory: false);
                            if FileManager.default.fileExists(atPath: localUploadDirUrl.path) {
                                try? FileManager.default.removeItem(at: localUploadDirUrl);
                            }
                        }
                    } else {
                        self.sharedDefaults?.removeObject(forKey: k);
                        let localUploadDirUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("upload", isDirectory: true).appendingPathComponent(hash, isDirectory: false);
                        if FileManager.default.fileExists(atPath: localUploadDirUrl.path) {
                            try? FileManager.default.removeItem(at: localUploadDirUrl);
                        }
                    }
                }
            }
        }
    }
    
    public func setValue(_ value: String?) {
        let currValue = getString();
        guard currValue != value else {
            return;
        }
        Settings.store.set(value, forKey: self.rawValue);
        Settings.valueChanged(forKey: self, oldValue: currValue, newValue: value);
    }
    
    public func setValue(_ value: Bool) {
        let currValue = getBool();
        guard currValue != value else {
            return;
        }
        Settings.store.set(value, forKey: self.rawValue);
        Settings.valueChanged(forKey: self, oldValue: currValue, newValue: value);
    }
    
    public func setValue(_ value: Int) {
        Settings.store.set(value, forKey: self.rawValue);
    }
    
    func bool() -> Bool {
        return getBool();
    }
    
    public func getBool() -> Bool {
        return Settings.store.bool(forKey: self.rawValue);
    }
    
    func string() -> String? {
        return getString();
    }
    
    public func getString() -> String? {
        return Settings.store.string(forKey: self.rawValue);
    }
    
    public func getInt() -> Int {
        return Settings.store.integer(forKey: self.rawValue);
    }
    
    public func integer() -> Int {
        return getInt();
    }
    
    fileprivate static func valueChanged(forKey key: Settings, oldValue: Any?, newValue: Any?) {
        var data: [AnyHashable:Any] = ["key": key.rawValue];
        if oldValue != nil {
            data["oldValue"] = oldValue!;
        }
        if newValue != nil {
            data["newValue"] = newValue!;
        }
        if isShared(key: key) {
            sharedDefaults!.set(newValue, forKey: key.rawValue);
        }
        NotificationCenter.default.post(name: Settings.SETTINGS_CHANGED, object: nil, userInfo: data);
    }
    
    fileprivate static func isShared(key: Settings) -> Bool {
        return key == Settings.RosterDisplayHiddenGroup || key == Settings.SharingViaHttpUpload || key == Settings.fileDownloadSizeLimit
    }
}

public enum AccountSettings {
    case messageSyncAuto(BareJID)
    case messageSyncPeriod(BareJID)
    case MessageSyncTime(BareJID)
    case PushNotificationsForAway(BareJID)
    case LastError(BareJID)
    case KnownServerFeatures(BareJID)
    case omemoRegistrationId(BareJID)
    case reconnectionLocation(BareJID)
    case pushHash(BareJID)
    
    public var account: BareJID {
        switch self {
        case .messageSyncAuto(let account):
            return account;
        case .messageSyncPeriod(let account):
            return account;
        case .MessageSyncTime(let account):
            return account;
        case .PushNotificationsForAway(let account):
            return account;
        case .LastError(let account):
            return account;
        case .KnownServerFeatures(let account):
            return account;
        case .omemoRegistrationId(let account):
            return account;
        case .reconnectionLocation(let account):
            return account;
        case .pushHash(let account):
            return account;
        }
    }
    
    public var name: String {
        switch self {
        case .messageSyncAuto( _):
            return "MessageSyncAutomatic";
        case .messageSyncPeriod( _):
            return "MessageSyncPeriod";
        case .MessageSyncTime( _):
            return "MessageSyncTime";
        case .PushNotificationsForAway( _):
            return "PushNotificationsForAway";
        case .LastError(_):
            return "LastError";
        case .KnownServerFeatures( _):
            return "KnownServerFeatures";
        case .omemoRegistrationId(_):
            return "omemoRegistrationId";
        case .reconnectionLocation(_):
            return "reconnectionLocation";
        case .pushHash(_):
            return "pushHash";
        }
    }
    
    public var key: String {
        return "accounts.\(account).\(name)";
    }
    
    public func string() -> String? {
        return getString();
    }
    
    public func getString() -> String? {
        return Settings.store.string(forKey: key);
    }

    func bool() -> Bool {
        return Settings.store.bool(forKey: key);
    }

    public func getBool() -> Bool {
        return bool();
    }
    
    func object() -> Any? {
        return Settings.store.object(forKey: key);
    }

    public func double() -> Double {
        return Settings.store.double(forKey: key);
    }

    public func getDouble() -> Double {
        return double();
    }
    
    func date() -> Date? {
        let value = Settings.store.double(forKey: key);
        if value == 0 {
            return nil;
        } else {
            return Date(timeIntervalSince1970: value);
        }
    }
    
    public func getDate() -> Date? {
        return date();
    }
    
    public func int() -> Int {
        return Settings.store.integer(forKey: key);
    }
    
    func uint32() -> UInt32? {
        return getUInt32();
    }
    
    func getUInt32() -> UInt32? {
        guard let tmp = Settings.store.string(forKey: key) else {
            return nil;
        }
        return UInt32(tmp);
    }
    
    public func getStrings() -> [String]? {
        let obj = Settings.store.object(forKey: key);
        return obj as? [String];
    }
    
    public func set(bool value: Bool) {
        Settings.store.set(value, forKey: key);
    }
    
    public func set(double value: Double) {
        Settings.store.set(value, forKey: key);
    }
    
    public func set(date value: Date?, condition: ComparisonResult? = nil) {
        if value == nil {
            Settings.store.set(nil, forKey: key);
        } else {
            let key = self.key;
            let oldValue = Settings.store.double(forKey: key)
            let newValue = value!.timeIntervalSince1970;
            if condition != nil {
                switch condition! {
                case .orderedAscending:
                    if oldValue >= newValue {
                        return;
                    }
                case .orderedDescending:
                    if oldValue <= newValue {
                        return;
                    }
                default:
                    break;
                }
            }
            Settings.store.set(newValue, forKey: key);
        }
    }
    
    public func set(string value: String?) {
        if value != nil {
            Settings.store.setValue(value, forKey: key);
        } else {
            Settings.store.removeObject(forKey: key);
        }
    }
    
    public func set(strings value: [String]?) {
        if value != nil {
            Settings.store.set(value, forKey: key);
        } else {
            Settings.store.removeObject(forKey: key);
        }
    }
    
    func set(uint32 value: UInt32?) {
        if value != nil {
            Settings.store.set(String(value!), forKey: key)
        } else {
            Settings.store.set(nil, forKey: key);
        }
    }
    
    func set(int value: Int) {
        Settings.store.set(value, forKey: key);
    }
    
    public static func removeSettings(for account: String) {
        let toRemove = Settings.store.dictionaryRepresentation().keys.filter { (key) -> Bool in
            return key.hasPrefix("Account-" + account + "-");
        };
        toRemove.forEach { (key) in
            Settings.store.removeObject(forKey: key);
        }
    }
    
    public static func initialize() {
        let accounts = AccountManager.getAccounts();
        let toRemove = Settings.store.dictionaryRepresentation().keys.filter { (key) -> Bool in
            return key.hasPrefix("Account-") && accounts.firstIndex(where: { (account) -> Bool in
                return key.hasPrefix("Account-\(account.stringValue)-");
            }) == nil;
        };
        toRemove.forEach { (key) in
            Settings.store.removeObject(forKey: key);
        }
    }
    
}
