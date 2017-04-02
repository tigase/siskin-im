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
            "RosterDisplayHiddenGroup" : false as AnyObject
        ];
        store.register(defaults: defaults);
    }
    
    public func setValue(_ value: Any?) {
        Settings.store.set(value, forKey: self.rawValue);
        Settings.valueChanged(forKey: self);
    }
    
    public func getBool() -> Bool {
        return Settings.store.bool(forKey: self.rawValue);
    }
    
    public func getString() -> String? {
        return Settings.store.string(forKey: self.rawValue);
    }
    
    fileprivate static func valueChanged(forKey key: Settings) {
        NotificationCenter.default.post(name: Settings.SETTINGS_CHANGED, object: nil, userInfo: ["key": key.rawValue]);
    }
}
