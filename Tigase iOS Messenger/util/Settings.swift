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
    
    private static var store: NSUserDefaults {
        return NSUserDefaults.standardUserDefaults();
    }
    
    public static func initialize() {
        let defaults: [String: AnyObject] = [
            "DeleteChatHistoryOnChatClose" : false,
            "EnableMessageCarbons" : true
        ];
        store.registerDefaults(defaults);
    }
    
    public func setValue(value: AnyObject?) {
        Settings.store.setObject(value, forKey: self.rawValue);
        Settings.valueChanged(self);
    }
    
    public func getBool() -> Bool {
        return Settings.store.boolForKey(self.rawValue);
    }
    
    public func getString() -> String? {
        return Settings.store.stringForKey(self.rawValue);
    }
    
    private static func valueChanged(key: Settings) {
        NSNotificationCenter.defaultCenter().postNotificationName("settingsChanged", object: nil, userInfo: ["key": key.rawValue]);
    }
}