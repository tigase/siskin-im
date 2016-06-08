//
// AccountManager.swift
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
import Security


public class AccountManager {
    
    static func getAccounts() -> [String] {
        var accounts = [String]();
        let query = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitAll, String(kSecReturnAttributes) : kCFBooleanTrue, String(kSecAttrService) : "xmpp" ];
        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(&result) {
            SecItemCopyMatching(query as CFDictionaryRef, UnsafeMutablePointer($0));
        }
        
        if lastResultCode == noErr {
            if let results = result as? [[String:NSObject]] {
                for var r in results {
                    let name = r[String(kSecAttrAccount)] as! String;
                    accounts.append(name);
                }
            }
            
        }
        return accounts;
    }

    static func getAccount(account:String) -> Account? {
        let query = AccountManager.getAccountQuery(account);
        
        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(&result) {
            SecItemCopyMatching(query as CFDictionaryRef, UnsafeMutablePointer($0));
        }
        
        if lastResultCode == noErr {
            if let r = result as? [String:NSObject] {
                if let data = r[String(kSecAttrGeneric)] as? NSData {
                    let dict = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? [String:AnyObject];
                    return Account(name: account, data: dict!);
                } else {
                    return Account(name: account);
                }
            }
        }
        return nil;
    }
    
    
    static func getAccountPassword(account:String) -> String? {
        let query = AccountManager.getAccountQuery(account, withData: kSecReturnData);

        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(&result) {
            SecItemCopyMatching(query as CFDictionaryRef, UnsafeMutablePointer($0));
        }
        
        if lastResultCode == noErr {
            if let data = result as? NSData {
                return String(data: data, encoding: NSUTF8StringEncoding);
            }
        }
        return nil;
    }
    
    static func updateAccountPassword(account:String, password:String) {
        let update = [ String(kSecValueData) : password.dataUsingEncoding(NSUTF8StringEncoding)! ];
        updateAccount(account, dataForUpdate: update);
    }
    
    static func deleteAccount(name:String) {
        var query = AccountManager.getAccountQuery(name);
        query.removeValueForKey(String(kSecMatchLimit));
        query.removeValueForKey(String(kSecReturnAttributes));
        let lastResultCode:OSStatus = SecItemDelete(query);
        NSNotificationCenter.defaultCenter().postNotificationName("accountConfigurationChanged", object: self, userInfo: ["account":name]);
        NSNotificationCenter.defaultCenter().postNotificationName("accountRemoved", object: self, userInfo: ["account":name]);
    }
    
    private static func updateAccount(account:String, dataForUpdate: [String:NSObject], notifyChange: Bool = true) {
        var query = AccountManager.getAccountQuery(account);
        
        var result:AnyObject?;
        
        var lastResultCode: OSStatus = withUnsafeMutablePointer(&result) {
            SecItemCopyMatching(query as CFDictionaryRef, UnsafeMutablePointer($0));
        }
        
        var found:[String:NSObject]? = nil;
        
        if lastResultCode == noErr {
            found = result as? [String:NSObject];
        }

        // Removing from query attributtes forbidden in insert/update query
        query.removeValueForKey(String(kSecMatchLimit));
        query.removeValueForKey(String(kSecReturnAttributes));

        if found == nil {
            found = query;
            for (k,v) in dataForUpdate {
                found?[k] = v;
            }
            found?[String(kSecAttrAccessible)] = kSecAttrAccessibleAfterFirstUnlock;
            lastResultCode = SecItemAdd(found!, nil);
        } else {
            var data = dataForUpdate
            data[String(kSecAttrAccessible)] = kSecAttrAccessibleAfterFirstUnlock;
            lastResultCode = SecItemUpdate(query, data);
        }
        if notifyChange {
            NSNotificationCenter.defaultCenter().postNotificationName("accountConfigurationChanged", object: self, userInfo: ["account": account]);
        }
    }
    
    private static func getAccountQuery(name:String, withData:CFString = kSecReturnAttributes) -> [String:NSObject] {
        return [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(withData) : kCFBooleanTrue, String(kSecAttrService) : "xmpp", String(kSecAttrAccount) : name ];
    }
    
    static func updateAccount(account:Account, notifyChange: Bool = true) {
        let data = NSKeyedArchiver.archivedDataWithRootObject(account.data);
        let update = [ String(kSecAttrGeneric) : data];
        updateAccount(account.name, dataForUpdate: update, notifyChange: notifyChange);
    }
    
    public class Account {
        
        private var data:[String:AnyObject];
        
        public let name:String;
        
        public var active:Bool {
            get {
                return (data["active"] as? Bool) ?? true;
            }
            set {
                data["active"] = newValue;
            }
        }
        
        public var password:String {
            get {
                return AccountManager.getAccountPassword(name)!;
            }
            set {
                AccountManager.updateAccountPassword(name, password: newValue);
            }
        }
        
        public var server:String? {
            get {
                return data["serverHost"] as? String;
            }
            set {
                if newValue != nil {
                    data["serverHost"] = newValue;
                } else {
                    data.removeValueForKey("serverHost");
                }
            }
        }
        
        public var rosterVersion:String? {
            get {
                return data["rosterVersion"] as? String;
            }
            set {
                if newValue != nil {
                    data["rosterVersion"] = newValue;
                } else {
                    data.removeValueForKey("rosterVersion");
                }
            }
        }
        
        public var presenceDescription: String? {
            get {
                return data["presenceDescription"] as? String;
            }
            set {
                if newValue != nil {
                    data["presenceDescription"] = newValue;
                } else {
                    data.removeValueForKey("presenceDescription");
                }
            }
        }
        
        public init(name:String) {
            self.name = name;
            self.data = [String:AnyObject]();
        }
        
        private init(name:String, data:[String:AnyObject]) {
            self.name = name;
            self.data = data;
        }
        
    }
}