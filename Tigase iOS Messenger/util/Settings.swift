//
// Settings.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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

import Foundation

public enum Settings: String {
    case DeleteChatHistoryOnChatClose
    case EnableMessageCarbons
    case StatusMessage
    case RosterType
    case RosterItemsOrder
    case RosterAvailableOnly
    case RosterDisplayHiddenGroup
    case AutoSubscribeOnAcceptedSubscriptionRequest
    case DeviceToken

    public static let SETTINGS_CHANGED = Notification.Name("settingsChanged");
    
    fileprivate static var store: UserDefaults {
        return UserDefaults.standard;
    }
    
    public static func initialize() {
        let defaults: [String: AnyObject] = [
            "DeleteChatHistoryOnChatClose" : false as AnyObject,
            "EnableMessageCarbons" : true as AnyObject,
            "RosterType" : "flat" as AnyObject,
            "RosterItemsOrder" : RosterSortingOrder.alphabetical.rawValue as AnyObject,
            "RosterAvailableOnly" : false as AnyObject,
            "RosterDisplayHiddenGroup" : false as AnyObject,
            "AutoSubscribeOnAcceptedSubscriptionRequest" : true as AnyObject
        ];
        store.register(defaults: defaults);
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
    
    public func getBool() -> Bool {
        return Settings.store.bool(forKey: self.rawValue);
    }
    
    public func getString() -> String? {
        return Settings.store.string(forKey: self.rawValue);
    }
    
    fileprivate static func valueChanged(forKey key: Settings, oldValue: Any?, newValue: Any?) {
        var data: [AnyHashable:Any] = ["key": key.rawValue];
        if oldValue != nil {
            data["oldValue"] = oldValue!;
        }
        if newValue != nil {
            data["newValue"] = newValue!;
        }
        NotificationCenter.default.post(name: Settings.SETTINGS_CHANGED, object: nil, userInfo: data);
    }
}

public enum AccountSettings {
    case MessageSyncAutomatic(String)
    case MessageSyncPeriod(String)
    case MessageSyncTime(String)
    
    public func getAccount() -> String {
        switch self {
        case .MessageSyncAutomatic(let account):
            return account;
        case .MessageSyncPeriod(let account):
            return account;
        case .MessageSyncTime(let account):
            return account;
        }
    }
    
    public func getName() -> String {
        switch self {
        case .MessageSyncAutomatic( _):
            return "MessageSyncAutomatic";
        case .MessageSyncPeriod( _):
            return "MessageSyncPeriod";
        case .MessageSyncTime( _):
            return "MessageSyncTime";
        }
    }
    
    fileprivate func getKey() -> String {
        return "Account-" + getAccount() + "-" + getName();
    }
    
    public func getString() -> String? {
        return Settings.store.string(forKey: getKey());
    }
    
    public func getBool() -> Bool {
        return Settings.store.bool(forKey: getKey());
    }
    
    public func getDouble() -> Double {
        return Settings.store.double(forKey: getKey());
    }
    
    public func getDate() -> Date? {
        let value = Settings.store.double(forKey: getKey());
        if value == 0 {
            return nil;
        } else {
            return Date(timeIntervalSince1970: value);
        }
    }
    
    public func set(bool value: Bool) {
        Settings.store.set(value, forKey: getKey());
    }
    
    public func set(double value: Double) {
        Settings.store.set(value, forKey: getKey());
    }
    
    public func set(date value: Date?, condition: ComparisonResult? = nil) {
        if value == nil {
            Settings.store.set(nil, forKey: getKey());
        } else {
            let key = getKey();
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
            return key.hasPrefix("Account-") && accounts.index(where: { (account) -> Bool in
                return !key.hasPrefix("Account-" + account + "-");
            }) == nil;
        };
        toRemove.forEach { (key) in
            Settings.store.removeObject(forKey: key);
        }
    }
    
}
