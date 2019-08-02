//
// DBChatStore.swift
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
import TigaseSwift

open class DBChatStoreWrapper: ChatStore {
    
    fileprivate let store: DBChatStore;
    fileprivate let sessionObject: SessionObject;
    
    open var count:Int {
        return store.count(for: sessionObject.userBareJid!);
    }
    
    open var items:[ChatProtocol] {
        return store.getChats(for: sessionObject.userBareJid!);
    }
    
    public let dispatcher: QueueDispatcher;
        
    public init(sessionObject:SessionObject) {
        self.sessionObject = sessionObject;
        self.store = DBChatStore.instance;
        self.dispatcher = store.dispatcher;
    }
    
    deinit {
        self.store.unloadChats(for: self.sessionObject.userBareJid!);
    }
    
    open func getChat<T>(with jid: BareJID, filter: @escaping (T) -> Bool) -> T? where T: ChatProtocol {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) as? T;
    }
    
    open func getAllChats<T>() -> [T] where T :  ChatProtocol {
        return items as! [T];
    }
    
    open func isFor(jid: BareJID) -> Bool {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) != nil;
    }
    
    open func open<T: AnyObject>(chat:ChatProtocol) -> T? {
        return store.open(for: sessionObject.userBareJid!, chat: chat);
    }
    
    open func close(chat:ChatProtocol) -> Bool {
        return store.close(for: sessionObject.userBareJid!, chat: chat);
    }
 
    open func initialize() {
        store.loadChats(for: sessionObject.userBareJid!, context: sessionObject.context);
    }
    
    public func deinitialize() {
        store.unloadChats(for: sessionObject.userBareJid!);
    }
}

open class DBChatStore {
    
    static let CHAT_OPENED = Notification.Name("CHAT_OPENED");
    static let CHAT_CLOSED = Notification.Name("CHAT_CLOSED");
    static let CHAT_UPDATED = Notification.Name("CHAT_UPDATED");

    public static let instance = DBChatStore.init();
    
    fileprivate static let CHATS_GET = "SELECT id, type, thread_id, resource, nickname, password, timestamp, options FROM chats WHERE account = :account AND jid = :jid";
    fileprivate static let CHATS_LIST = "SELECT id, jid, type, thread_id, resource, nickname, password, timestamp, options FROM chats WHERE account = :account";
    fileprivate static let CHAT_IS = "SELECT count(id) as count FROM chats WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_OPEN = "INSERT INTO chats (account, jid, timestamp, type, resource, thread_id) VALUES (:account, :jid, :timestamp, :type, :resource, :thread)";
    fileprivate static let ROOM_OPEN = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    fileprivate static let CHAT_CLOSE = "DELETE FROM chats WHERE id = :id";
    fileprivate static let CHATS_COUNT = "SELECT count(id) as count FROM chats WHERE account = :account";
    fileprivate static let UPDATE_CHAT_NAME = "UPDATE chats SET name = ? WHERE account = ? AND jid = ?";
    fileprivate static let UPDATE_CHAT_OPTIONS = "UPDATE chats SET options = ? WHERE account = ? AND jid = ?";
    
    fileprivate let dbConnection:DBConnection;
    
    fileprivate let getStmt: DBStatement;
    fileprivate let getAllStmt: DBStatement;
    fileprivate let isForStmt: DBStatement;
    fileprivate let openChatStmt: DBStatement;
    fileprivate let openRoomStmt: DBStatement;
    fileprivate let closeChatStmt: DBStatement;
    fileprivate let countStmt: DBStatement;
    fileprivate let updateChatOptionsStmt: DBStatement;
    fileprivate let updateChatNameStmt: DBStatement;
    
    fileprivate let updateMessageDraftStmt: DBStatement;
    fileprivate let getMessageDraftStmt: DBStatement;
    
    fileprivate var accountChats = [BareJID: AccountChats]();
    
    public let dispatcher: QueueDispatcher;
    
    public convenience init() {
        self.init(dbConnection: DBConnection.main, dispatcher: QueueDispatcher(label: "chat_store"));
    }
    
    public init(dbConnection:DBConnection, dispatcher: QueueDispatcher? = nil) {
        self.dbConnection = dbConnection;
        self.dispatcher = dispatcher ?? QueueDispatcher(queue: DispatchQueue(label: "db_chat_store_queue", attributes: DispatchQueue.Attributes.concurrent), queueTag: DispatchSpecificKey<DispatchQueue?>());

        self.getStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHATS_GET);
        self.getAllStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHATS_LIST);
        self.isForStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHAT_IS);
        self.openChatStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHAT_OPEN);
        self.openRoomStmt = try! self.dbConnection.prepareStatement(DBChatStore.ROOM_OPEN);
        self.closeChatStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHAT_CLOSE);
        self.countStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHATS_COUNT);
        self.getMessageDraftStmt = try! dbConnection.prepareStatement("SELECT message_draft FROM chats WHERE account = ? AND jid = ?");
        self.updateMessageDraftStmt = try! dbConnection.prepareStatement("UPDATE chats SET message_draft = ? WHERE account = ? AND jid = ?");
        self.updateChatNameStmt = try! self.dbConnection.prepareStatement(DBChatStore.UPDATE_CHAT_NAME);
        self.updateChatOptionsStmt = try! self.dbConnection.prepareStatement(DBChatStore.UPDATE_CHAT_OPTIONS);
        
        NotificationCenter.default.addObserver(self, selector: #selector(DBChatStore.accountRemoved), name: NSNotification.Name(rawValue: "accountRemoved"), object: nil);
    }
    
    open func count(for account: BareJID) -> Int {
        return dispatcher.sync {
            return self.accountChats[account]?.count ?? 0;
        }
    }
    
    open func getChats() -> [DBChatProtocol] {
        return dispatcher.sync {
            var items: [DBChatProtocol] = [];
            self.accountChats.values.forEach({ (accountChats) in
                items.append(contentsOf: accountChats.items);
            });
            return items;
        }
    }
    
    open func getChats(for account: BareJID) -> [DBChatProtocol] {
        return mapChats(for: account, map: { (chats) in
            return chats?.items ?? [];
        });
    }
    
    func mapChats<T>(for account: BareJID, map: (AccountChats?)->T) -> T {
        return dispatcher.sync {
            return map(accountChats[account]);
        }
    }
    
    func getChat(for account: BareJID, with jid: BareJID) -> DBChatProtocol? {
        return dispatcher.sync {
            return accountChats[account]?.get(with: jid);
        }
    }
        
    open func open<T>(for account: BareJID, chat: ChatProtocol) -> T? {
        return dispatcher.sync {
            let accountChats = self.accountChats[account]!;
            guard let dbChat = accountChats.get(with: chat.jid.bareJid) else {
                guard let dbChat = createChat(account: account, chat: chat) else {
                    return nil;
                }
                guard let result = accountChats.open(chat: dbChat) as? T else {
                    return nil;
                }
                
                NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: result);
                
                return result;
            }
            return dbChat as? T;
        }
    }
    
    open func close(for account: BareJID, chat:ChatProtocol) -> Bool {
        guard let dbChat = chat as? DBChatProtocol else {
            return false;
        }
        
        return dispatcher.sync {
            guard let accountChats = self.accountChats[account] else {
                return false;
            }
            
            guard accountChats.close(chat: dbChat) else {
                return false;
            }
            
            destroyChat(account: account, chat: dbChat);
            
//            if dbChat.unread > 0 {
//                self.unreadMessagesCount = self.unreadMessagesCount - dbChat.unread;
//
//                DBChatHistoryStore.instance.markAsRead(for: account, with: dbChat.jid.bareJid);
//            }
            
            NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: dbChat
            );
            
            return true;
        }
    }

    
    fileprivate func createChat(account: BareJID, chat: ChatProtocol) -> DBChatProtocol? {
        guard chat as? DBChatProtocol == nil else {
            return chat as? DBChatProtocol;
        }
        switch chat {
        case let c as Chat:
            let params:[String:Any?] = [ "account" : account, "jid" : c.jid.bareJid, "timestamp": NSDate(), "type" : 0, "resource" : c.jid.resource, "thread" : c.thread ];
            let id = try! self.openChatStmt.insert(params);
            return DBChat(id: id!, account: account, jid: c.jid.bareJid);
        case let r as Room:
            let params:[String:Any?] = [ "account" : account, "jid" : r.jid.bareJid, "timestamp": NSDate(), "type" : 1, "nickname" : r.nickname, "password" : r.password ];
            let id = try! self.openRoomStmt.insert(params);
            return DBRoom(id: id!, context: r.context, account: account, roomJid: r.roomJid, roomName: nil, nickname: r.nickname, password: r.password);
        default:
            return nil;
        }
    }
    
    fileprivate func destroyChat(account: BareJID, chat: DBChatProtocol) {
        let params: [String: Any?] = ["id": chat.id];
        _ = try! self.closeChatStmt.update(params);
    }
    
//    open func close(withId id: Int) -> Bool {
//        let params:[String:Any?] = [ "id" : id ];
//        return dispatcher.sync(flags: .barrier) {
//            return try! closeChatStmt.update(params) > 0;
//        }
//    }
    
    @objc open func accountRemoved(_ notification: NSNotification) {
        if let data = notification.userInfo {
            let account = BareJID(data["account"] as! String);
            self.unloadChats(for: account)
            _ = try! dbConnection.prepareStatement("DELETE FROM chats WHERE account = ?").update(account);
        }
    }
    
    open func loadChats(for account: BareJID, context: Context) {
        let params:[String:Any?] = [ "account" : account ];
        dispatcher.async {
            let chats = try! self.getAllStmt.query(params) { (cursor) -> DBChatProtocol? in
                let id: Int = cursor["id"]!;
                let type:Int = cursor["type"]!;
                let jid: BareJID = cursor["jid"]!;

                switch type {
                case 1:
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
                    let name: String? = cursor["name"];
                    let room = DBRoom(id: id, context: context, account: account, roomJid: jid, roomName: name, nickname: nickname, password: password);
                    room.lastMessageDate = cursor["timestamp"];
                    
                    if let dataStr: String = cursor["options"], let data = dataStr.data(using: .utf8), let options = try? JSONDecoder().decode(RoomOptions.self, from: data) {
                        room.options = options;
                    }
                    return room;
                default:
                    let c = DBChat(id: id, account: account, jid: jid);
                    if let dataStr: String = cursor["options"], let data = dataStr.data(using: .utf8), let options = try? JSONDecoder().decode(ChatOptions.self, from: data) {
                        c.options = options;
                    }
                    return c;
                }
            }
            let accountChats = AccountChats(items: chats);
            self.accountChats[account] = accountChats;
            chats.forEach { item in
                NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: item);
            }
        }
    }
    
    func unloadChats(for account: BareJID) {
        dispatcher.async {
            guard let accountChats = self.accountChats.removeValue(forKey: account) else {
                return;
            }
            
//            var unread = 0;
            accountChats.items.forEach { item in
//                unread = unread + item.unread;
                NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: item);
            }
//            if unread > 0 {
//                self.unreadMessagesCount = self.unreadMessagesCount - unread;
//            }
        }
    }
    
    open func updateChatName(account: BareJID, jid: BareJID, name: String?) {
        dispatcher.async {
            _ = try? self.updateChatNameStmt.update(name, account, jid);
            if let r = self.getChat(for: account, with: jid) as? DBRoom {
                r.roomName = name;
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: r, userInfo: nil);
                }
            }
        }
    }
    
    open func updateOptions<T>(for account: BareJID, jid: BareJID, options: T, completionHandler: (()->Void)?) where T: ChatOptionsProtocol {
        dispatcher.async {
            switch options {
            case let options as RoomOptions:
                let data = try? JSONEncoder().encode(options);
                let dataStr = data != nil ? String(data: data!, encoding: .utf8)! : nil;
                _ = try? self.updateChatOptionsStmt.update(dataStr, account, jid);
                if let c = self.getChat(for: account, with: jid) as? DBRoom {
                    c.options = options;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                }
                completionHandler?();
            case let options as ChatOptions:
                let data = try? JSONEncoder().encode(options);
                let dataStr = data != nil ? String(data: data!, encoding: .utf8)! : nil;
                _ = try? self.updateChatOptionsStmt.update(dataStr, account, jid);
                if let c = self.getChat(for: account, with: jid) as? DBChat {
                    c.options = options;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                }
                completionHandler?();
            default:
                completionHandler?();
                break;
            }
        }
    }
    
    open func updateMessageDraft(account: BareJID, jid: BareJID, draft: String?) {
        updateMessageDraftStmt.dispatcher.async {
            _ = try? self.updateMessageDraftStmt.update(draft, account, jid);
        }
    }
    
    open func getMessageDraft(account: BareJID, jid: BareJID, onResult: @escaping (String?)->Void) {
        getMessageDraftStmt.dispatcher.async {
            let text: String? = try! self.getMessageDraftStmt.queryFirstMatching(account, jid) { (cursor) -> String? in
                return cursor["message_draft"];
            }
            onResult(text);
        }
    }
    
    fileprivate func getContext(_ sessionObject: SessionObject) -> Context? {
        return sessionObject.context;
    }
    
    class AccountChats {
        
        fileprivate var chats = [BareJID: DBChatProtocol]();
        
        var count: Int {
            return chats.count;
        }
        
        var items: [DBChatProtocol] {
            return chats.values.map({ (chat) -> DBChatProtocol in
                return chat;
            });
        }
        
        init(items: [DBChatProtocol]) {
            items.forEach { item in
                self.chats[item.jid.bareJid] = item;
            }
        }
        
        func open(chat: DBChatProtocol) -> DBChatProtocol {
            guard let existingChat = chats[chat.jid.bareJid] else {
                chats[chat.jid.bareJid] = chat;
                return chat;
            }
            return existingChat;
        }
        
        func close(chat: DBChatProtocol) -> Bool {
            return chats.removeValue(forKey: chat.jid.bareJid) != nil;
        }
        
        func isFor(jid: BareJID) -> Bool {
            return chats[jid] != nil;
        }
        
        func get(with jid: BareJID) -> DBChatProtocol? {
            return chats[jid];
        }
        
//        func lastMessageTimestamp() -> Date {
//            var timestamp = Date(timeIntervalSince1970: 0);
//            chats.values.forEach { (chat) in
//                guard chat.lastMessage != nil else {
//                    return;
//                }
//                timestamp = max(timestamp, chat.timestamp);
//            }
//            return timestamp;
//        }
    }
}

public protocol  DBChatProtocol: ChatProtocol {
    
    var id: Int { get };
    var account: BareJID { get }
    
}

//extension ChatProtocol {
//
//    var id:Int? {
//        switch self {
//        case let c as DBChat:
//            return c.id;
//        case let r as DBRoom:
//            return r.id;
//        default:
//            return nil;
//        }
//    }
//
//}

public protocol ChatOptionsProtocol {
    
}

public struct ChatOptions: Codable, ChatOptionsProtocol {
    
    var encryption: ChatEncryption?;
    
    init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        if let val = try container.decodeIfPresent(String.self, forKey: .encryption) {
            encryption = ChatEncryption(rawValue: val);
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if encryption != nil {
            try container.encode(encryption!.rawValue, forKey: .encryption);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case encryption = "encrypt"
    }
}

class DBChat: Chat, DBChatProtocol {

    let id: Int;
    let account: BareJID;
    fileprivate(set) var options: ChatOptions = ChatOptions();
    
    init(id: Int, account: BareJID, jid: BareJID) {
        self.id = id;
        self.account = account;
        super.init(jid: JID(jid), thread: nil);
    }
 
    func modifyOptions(_ fn: @escaping (inout ChatOptions)->Void, completionHandler: (()->Void)? = nil) {
        DispatchQueue.main.async {
            var options = self.options;
            fn(&options);
            DBChatStore.instance.updateOptions(for: self.account, jid: self.jid.bareJid, options: options, completionHandler: completionHandler);
        }
    }

}

class DBRoom: Room, DBChatProtocol {
    
    let id: Int;
    let account: BareJID;
    var roomName: String? = nil;
    fileprivate(set) var options: RoomOptions = RoomOptions();
    
    init(id: Int, context: Context, account: BareJID, roomJid: BareJID, roomName: String?, nickname: String, password: String?) {
        self.id = id;
        self.account = account;
        super.init(context: context, roomJid: roomJid, nickname: nickname);
        self.password = password;
    }
    
    func modifyOptions(_ fn: @escaping (inout RoomOptions)->Void, completionHandler: (()->Void)? = nil) {
        DispatchQueue.main.async {
            var options = self.options;
            fn(&options);
            DBChatStore.instance.updateOptions(for: self.account, jid: self.roomJid, options: options, completionHandler: completionHandler);
        }
    }
}

public enum ChatEncryption: String {
    case none = "none";
    case omemo = "omemo";
}
