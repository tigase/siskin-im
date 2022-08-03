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
import Martin
import Combine

open class AccountManager {
    
    private static let dispatcher = QueueDispatcher(label: "AccountManager");
    private static var accounts: [BareJID: Account] = [:];
    
    static let accountEventsPublisher = PassthroughSubject<Event,Never>();
    static var defaultAccount: BareJID? {
        get {
            return BareJID(Settings.defaultAccount);
        }
        set {
            Settings.defaultAccount = newValue?.stringValue;
        }
    }
    
    public static let saltedPasswordCache = AccountManagerScramSaltedPasswordCache();
    
    static func getActiveAccounts() -> [Account] {
        return getAccounts().compactMap({ jid -> Account? in
            guard let account = getAccount(for: jid), account.active else {
                return nil;
            }
            return account;
        });
    }
    
    static func getAccounts() -> [BareJID] {
        self.dispatcher.sync {
            guard accounts.isEmpty else {
                return Array(accounts.keys).sorted(by: { (j1, j2) -> Bool in
                    j1.stringValue.compare(j2.stringValue) == .orderedAscending;
                });
            }
            
            let query = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitAll, String(kSecReturnAttributes) : kCFBooleanTrue as Any, String(kSecAttrService) : "xmpp" ] as [String : Any];
            var result: CFTypeRef?;

            guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
                return [];
            }
            
            guard let results = result as? [[String: NSObject]] else {
                return [];
            }

            let accounts = results.filter({ $0[kSecAttrAccount as String] != nil}).map { item -> BareJID in
                return BareJID(item[kSecAttrAccount as String] as! String);
            }.sorted(by: { (j1, j2) -> Bool in
                j1.stringValue.compare(j2.stringValue) == .orderedAscending
            });
            
            for account in accounts {
                if let item = getAccountInt(for: account) {
                    self.accounts[account] = item;
                }
            }
            return accounts;
        }
    }

    static func getAccount(for jid: BareJID) -> Account? {
        return self.dispatcher.sync {
            return self.accounts[jid];
        }
    }
    
    private static func getAccountInt(for jid: BareJID) -> Account? {
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
    
    static func save(account toSave: Account, reconnect: Bool = true) throws {
        try self.dispatcher.sync {
            var account = toSave;
            var query = AccountManager.getAccountQuery(account.name.stringValue);
            query.removeValue(forKey: String(kSecMatchLimit));
            query.removeValue(forKey: String(kSecReturnAttributes));

            var update: [String: Any] = [ kSecAttrGeneric as String: try! NSKeyedArchiver.archivedData(withRootObject: account.data, requiringSecureCoding: false), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock ];

            if let newPassword = account.newPassword {
                update[kSecValueData as String] = newPassword.data(using: .utf8)!;
            }

            if getAccount(for: account.name) == nil {
                query.merge(update) { (v1, v2) -> Any in
                    return v1;
                }
                if let error = AccountManagerError(status: SecItemAdd(query as CFDictionary, nil)) {
                    throw error;
                }
            } else {
                if let error = AccountManagerError(status: SecItemUpdate(query as CFDictionary, update as CFDictionary)) {
                    throw error;
                }
            }
            
            if account.newPassword != nil {
                account.saltedPassword = nil;
            }
            account.newPassword = nil;
            
            if defaultAccount == nil {
                defaultAccount = account.name;
            }
                         
            self.accounts[account.name] = account;
                        
            DispatchQueue.main.async {
                self.accountEventsPublisher.send(account.active ? .enabled(account, reconnect) : .disabled(account));
            }
        }
    }

    static func deleteAccount(for jid: BareJID) throws {
        guard let account = getAccount(for: jid) else {
            return;
        }
        try delete(account: account);
    }
    
    static func delete(account: Account) throws {
        try dispatcher.sync {
            var query = AccountManager.getAccountQuery(account.name.stringValue);
            query.removeValue(forKey: String(kSecMatchLimit));
            query.removeValue(forKey: String(kSecReturnAttributes));
            
            if let error = AccountManagerError(status: SecItemDelete(query as CFDictionary)) {
                throw error;
            }
            
            self.accounts.removeValue(forKey: account.name);
            NotificationEncryptionKeys.set(key: nil, for: account.name);
            DispatchQueue.main.async {
                self.accountEventsPublisher.send(.removed(account));
            }        }
    }
    
    fileprivate static func getAccountQuery(_ name:String, withData:CFString = kSecReturnAttributes) -> [String: Any] {
        return [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(withData) : kCFBooleanTrue!, String(kSecAttrService) : "xmpp" as NSObject, String(kSecAttrAccount) : name as NSObject ];
    }
    
    enum Event {
            case enabled(Account,Bool)
            case disabled(Account)
            case removed(Account)
        }
        
    struct AccountManagerError: LocalizedError, CustomDebugStringConvertible {
        let status: OSStatus;
        let message: String?;
        
        var errorDescription: String? {
            return "\(NSLocalizedString("It was not possible to modify account.", comment: "error description message"))\n\(message ?? "\(NSLocalizedString("Error code", comment: "error description message - detail")): \(status)")";
        }
        
        var failureReason: String? {
            return message;
        }
        
        var recoverySuggestion: String? {
            return NSLocalizedString("Try again. If removal failed, try accessing Keychain to update account credentials manually.", comment: "error recovery suggestion");
        }
        
        var debugDescription: String {
            return "AccountManagerError(status: \(status), message: \(message ?? "nil"))";
        }
        
        init?(status: OSStatus) {
            guard status != noErr else {
                return nil;
            }
            self.status = status;
            message = SecCopyErrorMessageString(status, nil) as String?;
        }
    }
    
    struct Account {
        
        public var state = CurrentValueSubject<XMPPClient.State,Never>(.disconnected());
        
        fileprivate var data:[String: Any];
        fileprivate var newPassword: String?;
        
        public let name: BareJID;
        
        public var active:Bool {
            get {
                return (data["active"] as? Bool) ?? true;
            }
            set {
                data["active"] = newValue as AnyObject?;
            }
        }
        
        public var password:String? {
            get {
                guard newPassword == nil else {
                    return newPassword;
                }
                return AccountManager.getAccountPassword(for: name);
            }
            set {
                self.newPassword = newValue;
            }
        }
        
        public var nickname: String? {
            get {
                guard let nick = data["nickname"] as? String, !nick.isEmpty else {
                    return name.localPart;
                }
                return nick;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "nickname");
                } else {
                    data["nickname"] = newValue;
                }
            }
        }
        
        public var server:String? {
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
        
        public var rosterVersion:String? {
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
        
        public var presenceDescription: String? {
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
        
        public var pushNotifications: Bool {
            get {
                return (data["pushNotifications"] as? Bool) ?? false;
            }
            set {
                data["pushNotifications"] = newValue as AnyObject?;
            }
        }
        
        public var pushSettings: SiskinPushNotificationsModule.PushSettings? {
            get {
                return SiskinPushNotificationsModule.PushSettings(dictionary: data["push"] as? [String: Any]);
            }
            set {
                data["push"] = newValue?.dictionary();
                data.removeValue(forKey: "pushServiceJid");
                data.removeValue(forKey: "pushServiceNode");
            }
        }
        
        public var serverCertificate: ServerCertificateInfo? {
            get {
                return data["serverCert"] as? ServerCertificateInfo;
            }
            set {
                if newValue != nil {
                    data["serverCert"] = newValue;
                } else {
                    data.removeValue(forKey: "serverCert");
                }
            }
        }
        
        public var saltedPassword: SaltEntry? {
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
        
        public var disableTLS13: Bool {
            get {
                return data["disableTLS13"] as? Bool ?? false;
            }
            set {
                if newValue {
                    data["disableTLS13"] = newValue;
                } else {
                    data.removeValue(forKey: "disableTLS13");
                }
            }
        }
        
        public var endpoint: SocketConnectorNetwork.Endpoint? {
            get {
                guard let values = data["endpoint"] as? [String: Any], let protoStr = values["proto"] as? String, let proto = ConnectorProtocol(rawValue: protoStr), let host = values["host"] as? String, let port = values["port"] as? Int else {
                    return nil;
                }
                return SocketConnectorNetwork.Endpoint(proto: proto, host: host, port: port);
            }
            set {
                if let value = newValue {
                    data["endpoint"] = [ "proto": value.proto.rawValue, "host": value.host, "port": value.port ];
                } else {
                    data.removeValue(forKey: "endpoint");
                }
            }
        }
                
        public init(name: BareJID, data: [String: Any]? = nil) {
            self.name = name;
            self.data = data ?? [String: Any]();
        }
        
        public mutating func acceptCertificate(_ certData: SslCertificateInfo?) {
            guard let data = certData else {
                self.serverCertificate = nil;
                return;
            }
            self.serverCertificate = ServerCertificateInfo(sslCertificateInfo: data, accepted: true);
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
