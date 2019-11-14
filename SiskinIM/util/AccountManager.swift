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
import Shared
import TigaseSwift


open class AccountManager {
    
    public static let ACCOUNT_CHANGED = Notification.Name(rawValue: "accountChanged");
    
    public static let saltedPasswordCache = AccountManagerScramSaltedPasswordCache();
    
    static func getActiveAccounts() -> [BareJID] {
        return getAccounts().filter({ jid -> Bool in
            return AccountManager.getAccount(for: jid)?.active ?? false;
        });
    }
    
    static func getAccounts() -> [BareJID] {
        let query = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitAll, String(kSecReturnAttributes) : kCFBooleanTrue as Any, String(kSecAttrService) : "xmpp" ] as [String : Any];
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return [];
        }
        
        guard let results = result as? [[String: NSObject]] else {
            return [];
        }
        
        return results.map { item -> BareJID in
            return BareJID(item[kSecAttrAccount as String] as! String);
            }.sorted(by: { (j1, j2) -> Bool in
                j1.stringValue.compare(j2.stringValue) == .orderedAscending
            });
    }

    static func getAccount(for jid: BareJID) -> Account? {
        let query = AccountManager.getAccountQuery(jid.stringValue);
        
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return nil;
        }
        
        guard let r = result as? [String: NSObject] else {
            return nil;
        }
        
        var dict: [String: Any]? = nil;
        if let data = r[String(kSecAttrGeneric)] as? NSData {
            dict = NSKeyedUnarchiver.unarchiveObject(with: data as Data) as? [String: Any];
        }
        
        return Account(name: jid, data: dict);
    }
    
    static func getAccount(for sessionObject: SessionObject) -> Account? {
        guard let jid = sessionObject.userBareJid else {
            return nil;
        }
        return AccountManager.getAccount(for: jid);
    }
    
    
    static func getAccountPassword(for account: BareJID) -> String? {
        let query = AccountManager.getAccountQuery(account.stringValue, withData: kSecReturnData);
        
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return nil;
        }
        
        guard let data = result as? Data else {
            return nil;
        }
        
        return String(data: data, encoding: .utf8);
    }
    
    static func save(account: Account, withPassword: String? = nil) -> Bool {
        var query = AccountManager.getAccountQuery(account.name.stringValue);
        query.removeValue(forKey: String(kSecMatchLimit));
        query.removeValue(forKey: String(kSecReturnAttributes));

        var update: [String: Any] = [ kSecAttrGeneric as String: try! NSKeyedArchiver.archivedData(withRootObject: account.data, requiringSecureCoding: false), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock ];

        if let password = withPassword {
            update[kSecValueData as String] = password.data(using: String.Encoding.utf8)!;
        }

        var result = false;
        let prevAccount = getAccount(for: account.name);
        if prevAccount == nil {
            query.merge(update) { (v1, v2) -> Any in
                return v1;
            }
            result = SecItemAdd(query as CFDictionary, nil) == noErr;
        } else {
            result = SecItemUpdate(query as CFDictionary, update as CFDictionary) == noErr;
        }
        
        // notify about account change only if password or active is changed!
        if withPassword != nil || ((prevAccount?.active ?? false) != account.active) {
            AccountManager.accountChanged(account: account);
        }
        return result;
    }

    static func deleteAccount(for jid: BareJID) -> Bool {
        guard let account = getAccount(for: jid) else {
            return false;
        }
        return delete(account: account);
    }
    
    static func delete(account: Account) -> Bool {
        var query = AccountManager.getAccountQuery(account.name.stringValue);
        query.removeValue(forKey: String(kSecMatchLimit));
        query.removeValue(forKey: String(kSecReturnAttributes));
        
        guard SecItemDelete(query as CFDictionary) == noErr else {
            return false;
        }
        
        AccountSettings.removeSettings(for: account.name.stringValue);
        NotificationEncryptionKeys.set(key: nil, for: account.name);
        AccountManager.accountChanged(account: account);

        return true;
    }
    
    private static func accountChanged(account: Account) {
        NotificationCenter.default.post(name: AccountManager.ACCOUNT_CHANGED, object: account);
    }
    
    fileprivate static func getAccountQuery(_ name:String, withData:CFString = kSecReturnAttributes) -> [String: Any] {
        return [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(withData) : kCFBooleanTrue, String(kSecAttrService) : "xmpp" as NSObject, String(kSecAttrAccount) : name as NSObject ];
    }
    
    open class Account {
        
        fileprivate var data:[String: Any];
        
        public let name: BareJID;
        
        open var active:Bool {
            get {
                return (data["active"] as? Bool) ?? true;
            }
            set {
                data["active"] = newValue as AnyObject?;
            }
        }
        
        open var password:String? {
            get {
                return AccountManager.getAccountPassword(for: name);
            }
            set {
                AccountManager.save(account: self, withPassword: newValue);
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
        
        open var pushSettings: SiskinPushNotificationsModule.PushSettings? {
            get {
                guard let settings = SiskinPushNotificationsModule.PushSettings(dictionary: data["push"] as? [String: Any]) else {
                    guard let pushServiceNode = self.pushServiceNode, let deviceId = Settings.DeviceToken.string() else {
                        return nil;
                    }
                    return SiskinPushNotificationsModule.PushSettings(jid: self.pushServiceJid ?? XmppService.pushServiceJid, node: pushServiceNode, deviceId: deviceId, encryption: false);
                }
                return settings;
            }
            set {
                data["push"] = newValue?.dictionary();
                data.removeValue(forKey: "pushServiceJid");
                data.removeValue(forKey: "pushServiceNode");
            }
        }
        
        private var pushServiceJid: JID? {
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
        
        private var pushServiceNode: String? {
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
                
        public init(name: BareJID, data: [String: Any]? = nil) {
            self.name = name;
            self.data = data ?? [String: Any]();
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
