//
// AccountManager.swift
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
import Security
import TigaseSwift


open class AccountManager {
    
    public static let ACCOUNT_CONFIGURATION_CHANGED = Notification.Name("accountConfigurationChanged");
    public static let ACCOUNT_REMOVED = Notification.Name("accountRemoved");
    
    public static let saltedPasswordCache = AccountManagerScramSaltedPasswordCache();
    
    static func getAccounts() -> [String] {
        var accounts = [String]();
        let query = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitAll, String(kSecReturnAttributes) : kCFBooleanTrue as Any, String(kSecAttrService) : "xmpp" ] as [String : Any];
        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
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

    static func getAccount(forJid account:String) -> Account? {
        let query = AccountManager.getAccountQuery(account);
        
        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
        }
        
        if lastResultCode == noErr {
            if let r = result as? [String:NSObject] {
                if let data = r[String(kSecAttrGeneric)] as? NSData {
                    let dict = NSKeyedUnarchiver.unarchiveObject(with: data as Data) as? [String:AnyObject];
                    return Account(name: account, data: dict!);
                } else {
                    return Account(name: account);
                }
            }
        }
        return nil;
    }
    
    static func getAccount(for sessionObject: SessionObject) -> Account? {
        guard let accountName = sessionObject.userBareJid?.stringValue else {
            return nil;
        }
        return AccountManager.getAccount(forJid: accountName);
    }
    
    
    static func getAccountPassword(forJid account:String) -> String? {
        let query = AccountManager.getAccountQuery(account, withData: kSecReturnData);

        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
        }
        
        if lastResultCode == noErr {
            if let data = result as? NSData {
                return String(data: data as Data, encoding: String.Encoding.utf8);
            }
        }
        return nil;
    }
    
    static func updateAccount(forJid account:String, password:String) {
        let update = [ String(kSecValueData) : password.data(using: String.Encoding.utf8)! ];
        updateAccount(account, dataForUpdate: update as [String : NSObject]);
    }
    
    static func deleteAccount(forJid name:String) {
        var query = AccountManager.getAccountQuery(name);
        query.removeValue(forKey: String(kSecMatchLimit));
        query.removeValue(forKey: String(kSecReturnAttributes));
        _ = SecItemDelete(query as CFDictionary);
        AccountSettings.removeSettings(for: name);
        NotificationCenter.default.post(name: AccountManager.ACCOUNT_CONFIGURATION_CHANGED, object: self, userInfo: ["account":name]);
        NotificationCenter.default.post(name: AccountManager.ACCOUNT_REMOVED, object: self, userInfo: ["account":name]);
    }
    
    fileprivate static func updateAccount(_ account:String, dataForUpdate: [String:NSObject], notifyChange: Bool = true) {
        var query = AccountManager.getAccountQuery(account);
        
        var result:AnyObject?;
        
        var lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
            return SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
        }
        
        var found:[String:NSObject]? = nil;
        
        if lastResultCode == noErr {
            found = result as? [String:NSObject];
        }

        // Removing from query attributtes forbidden in insert/update query
        query.removeValue(forKey: String(kSecMatchLimit));
        query.removeValue(forKey: String(kSecReturnAttributes));

        if found == nil {
            found = query;
            for (k,v) in dataForUpdate {
                found?[k] = v;
            }
            found?[String(kSecAttrAccessible)] = kSecAttrAccessibleAfterFirstUnlock;
            lastResultCode = SecItemAdd(found! as CFDictionary, nil);
        } else {
            var data = dataForUpdate
            data[String(kSecAttrAccessible)] = kSecAttrAccessibleAfterFirstUnlock;
            lastResultCode = SecItemUpdate(query as CFDictionary, data as CFDictionary);
        }
        if notifyChange {
            NotificationCenter.default.post(name: AccountManager.ACCOUNT_CONFIGURATION_CHANGED, object: self, userInfo: ["account": account]);
        }
    }
    
    fileprivate static func getAccountQuery(_ name:String, withData:CFString = kSecReturnAttributes) -> [String:NSObject] {
        return [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(withData) : kCFBooleanTrue, String(kSecAttrService) : "xmpp" as NSObject, String(kSecAttrAccount) : name as NSObject ];
    }
    
    static func updateAccount(_ account:Account, notifyChange: Bool = true) {
        let data = NSKeyedArchiver.archivedData(withRootObject: account.data);
        let update = [ String(kSecAttrGeneric) : data];
        updateAccount(account.name, dataForUpdate: update as [String : NSObject], notifyChange: notifyChange);
    }
    
    open class Account {
        
        fileprivate var data:[String:AnyObject];
        
        public let name:String;
        
        open var active:Bool {
            get {
                return (data["active"] as? Bool) ?? true;
            }
            set {
                data["active"] = newValue as AnyObject?;
            }
        }
        
        open var password:String {
            get {
                return AccountManager.getAccountPassword(forJid: name)!;
            }
            set {
                AccountManager.updateAccount(forJid: name, password: newValue);
            }
        }
        
        open var server:String? {
            get {
                return data["serverHost"] as? String;
            }
            set {
                if newValue != nil {
                    data["serverHost"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "serverHost");
                }
            }
        }
        
        open var rosterVersion:String? {
            get {
                return data["rosterVersion"] as? String;
            }
            set {
                if newValue != nil {
                    data["rosterVersion"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "rosterVersion");
                }
            }
        }
        
        open var presenceDescription: String? {
            get {
                return data["presenceDescription"] as? String;
            }
            set {
                if newValue != nil {
                    data["presenceDescription"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "presenceDescription");
                }
            }
        }
        
        open var pushNotifications: Bool {
            get {
                return (data["pushNotifications"] as? Bool) ?? false;
            }
            set {
                data["pushNotifications"] = newValue as AnyObject?;
            }
        }
        
        open var pushServiceJid: JID? {
            get {
                return JID(data["pushServiceJid"] as? String);
            }
            set {
                if newValue != nil {
                    data["pushServiceJid"] = newValue!.stringValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "pushServiceJid");
                }
            }
        }
        
        open var pushServiceNode: String? {
            get {
                return data["pushServiceNode"] as? String;
            }
            set {
                if newValue != nil {
                    data["pushServiceNode"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "pushServiceNode");
                }
            }
        }
        
        open var serverCertificate: [String: Any]? {
            get {
                return data["serverCert"] as? [String: Any];
            }
            set {
                if newValue != nil {
                    data["serverCert"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "serverCert");
                }
            }
        }
        
        open var saltedPassword: SaltEntry? {
            get {
                return SaltEntry(dict: data["saltedPassword"] as? [String: Any]);
            }
            set {
                if newValue != nil {
                    data["saltedPassword"] = newValue!.dictionary() as AnyObject?;
                } else {
                    data.removeValue(forKey: "saltedPassword");
                }
            }
        }
        
        public init(name:String) {
            self.name = name;
            self.data = [String:AnyObject]();
        }
        
        fileprivate init(name:String, data:[String:AnyObject]) {
            self.name = name;
            self.data = data;
        }
        
        open func acceptCertificate(_ certData: SslCertificateInfo?) {
            guard certData != nil else {
                self.serverCertificate = nil;
                return;
            }
            self.serverCertificate = [ "accepted" : true, "cert-hash-sha1" : certData!.details.fingerprintSha1 as Any ];
        }
    }
    
    open class SaltEntry {
        public let id: String;
        public let value: [UInt8];
        
        convenience init?(dict: [String: Any]?) {
            guard let id = dict?["id"] as? String, let value = dict?["value"] as? [UInt8] else {
                return nil;
            }
            self.init(id: id, value: value);
        }
        
        public init(id: String, value: [UInt8]) {
            self.id = id;
            self.value = value;
        }
        
        open func dictionary() -> [String: Any] {
            return ["id": id, "value": value];
        }
    }
}
