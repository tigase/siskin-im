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
import Shared
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
    
    static let UNREAD_MESSAGES_COUNT_CHANGED = Notification.Name("UNREAD_NOTIFICATIONS_COUNT_CHANGED");
    static let CHAT_OPENED = Notification.Name("CHAT_OPENED");
    static let CHAT_CLOSED = Notification.Name("CHAT_CLOSED");
    static let CHAT_UPDATED = Notification.Name("CHAT_UPDATED");
    static let CHAT_CREATED = Notification.Name("CHAT_CREATED");
    static let CHAT_DESTROYED = Notification.Name("CHAT_DESTROYED");

    public static let instance = DBChatStore.init();
    
    fileprivate static let CHATS_GET = "SELECT id, type, thread_id, resource, nickname, password, timestamp, options FROM chats WHERE account = :account AND jid = :jid";
    fileprivate static let CHATS_LIST = "SELECT c.id, c.type, c.jid, c.name, c.nickname, c.password, c.timestamp as creation_timestamp, cr.timestamp as read_till, last.timestamp as timestamp, last1.data, last1.encryption as lastEncryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread, c.options FROM chats c LEFT JOIN chats_read cr on c.account = cr.account AND c.jid = cr.jid LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account LEFT JOIN chat_history last1 ON last1.account = c.account AND last1.jid = c.jid AND last1.timestamp = last.timestamp WHERE c.account = :account";
    fileprivate static let CHAT_IS = "SELECT count(id) as count FROM chats WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_OPEN = "INSERT INTO chats (account, jid, timestamp, type, resource, thread_id) VALUES (:account, :jid, :timestamp, :type, :resource, :thread)";
    fileprivate static let ROOM_OPEN = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    fileprivate static let CHAT_CLOSE = "DELETE FROM chats WHERE id = :id";
    fileprivate static let CHATS_COUNT = "SELECT count(id) as count FROM chats WHERE account = :account";
    fileprivate static let GET_LAST_MESSAGE = "SELECT last.timestamp as timestamp, last1.data, last1.encryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid GROUP BY ch.account, ch.jid) last LEFT JOIN chat_history last1 ON last1.account = last.account AND last1.jid = last.jid AND last1.timestamp = last.timestamp";
    fileprivate static let GET_LAST_MESSAGE_TIMESTAMP_FOR_ACCOUNT = "SELECT max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND (ch.state % 2) = 0";
    fileprivate static let UPDATE_CHAT_NAME = "UPDATE chats SET name = ? WHERE account = ? AND jid = ?";
    fileprivate static let UPDATE_CHAT_OPTIONS = "UPDATE chats SET options = ? WHERE account = ? AND jid = ?";
    
    fileprivate let dbConnection:DBConnection;
    
    fileprivate let getStmt: DBStatement;
    fileprivate let getAllStmt: DBStatement;
    fileprivate let isForStmt: DBStatement;
    fileprivate let openChatStmt: DBStatement;
    fileprivate let openRoomStmt: DBStatement;
    fileprivate let getLastMessageStmt: DBStatement;
    fileprivate let getLastMessageTimestampForAccountStmt: DBStatement;
    fileprivate let closeChatStmt: DBStatement;
    fileprivate let countStmt: DBStatement;
    fileprivate let updateChatOptionsStmt: DBStatement;
    fileprivate let updateChatNameStmt: DBStatement;
    
    
    fileprivate let updateMessageDraftStmt: DBStatement;
    fileprivate let getMessageDraftStmt: DBStatement;
    
    fileprivate var accountChats = [BareJID: AccountChats]();
    
    fileprivate var deleteReadTillStmt: DBStatement;
    
    var unreadChats: Int {
        if unreadMessagesCount > 0 {
            return getChats().filter({ (chat) -> Bool in
                return chat.unread > 0;
            }).count;
        } else {
            return 0;
        }
    }
    fileprivate(set) var unreadMessagesCount = 0 {
        willSet {
            if newValue < 0 {
                print("setting to ", newValue);
            }
        }
        didSet {
            let value = self.unreadMessagesCount;
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: value);
            }
        }
    }
    
    public let dispatcher: QueueDispatcher;
    
    public convenience init() {
        self.init(dbConnection: DBConnection.main, dispatcher: QueueDispatcher(label: "chat_store"));
    }
    
    public init(dbConnection:DBConnection, dispatcher: QueueDispatcher? = nil) {
        self.dbConnection = dbConnection;
        self.dispatcher = dispatcher ?? QueueDispatcher(label: "db_chat_store_queue", attributes: DispatchQueue.Attributes.concurrent);

        self.getStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHATS_GET);
        self.getAllStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHATS_LIST);
        self.isForStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHAT_IS);
        self.openChatStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHAT_OPEN);
        self.openRoomStmt = try! self.dbConnection.prepareStatement(DBChatStore.ROOM_OPEN);
        self.closeChatStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHAT_CLOSE);
        self.countStmt = try! self.dbConnection.prepareStatement(DBChatStore.CHATS_COUNT);
        self.getMessageDraftStmt = try! dbConnection.prepareStatement("SELECT message_draft FROM chats WHERE account = ? AND jid = ?");
        self.updateMessageDraftStmt = try! dbConnection.prepareStatement("UPDATE chats SET message_draft = ? WHERE account = ? AND jid = ? AND IFNULL(message_draft, '') <> IFNULL(?, '')");
        getLastMessageStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_LAST_MESSAGE);
        getLastMessageTimestampForAccountStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_LAST_MESSAGE_TIMESTAMP_FOR_ACCOUNT);
        self.updateChatNameStmt = try! self.dbConnection.prepareStatement(DBChatStore.UPDATE_CHAT_NAME);
        self.updateChatOptionsStmt = try! self.dbConnection.prepareStatement(DBChatStore.UPDATE_CHAT_OPTIONS);
        self.getReadTillStmt = try! DBConnection.main.prepareStatement("SELECT timestamp FROM chats_read WHERE account = :account AND jid = :jid");
        if #available(iOS 12.0, *) {
            self.updateReadTillStmt = try! DBConnection.main.prepareStatement("INSERT INTO chats_read (account, jid, timestamp) VALUES (:account, :jid, :before) ON CONFLICT(account, jid) DO UPDATE SET timestamp = max(timestamp, excluded.timestamp)");
        } else {
            self.updateReadTillStmt = try! DBConnection.main.prepareStatement("INSERT INTO chats_read (account, jid, timestamp) VALUES (:account, :jid, :before)");
        }
        self.deleteReadTillStmt = try! DBConnection.main.prepareStatement("DELETE FROM chats_read WHERE account = :account AND jid = :jid");
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
                NotificationCenter.default.post(name: DBChatStore.CHAT_CREATED, object: result);
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

            if dbChat.unread > 0 {
                DBChatHistoryStore.instance.markAsRead(for: account, with: dbChat.jid.bareJid, before: dbChat.timestamp);
            }
            if Settings.DeleteChatHistoryOnChatClose.getBool() {
                DBChatHistoryStore.instance.deleteMessages(for: account, with: chat.jid.bareJid);
            }

            NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: dbChat);
            NotificationCenter.default.post(name: DBChatStore.CHAT_DESTROYED, object: dbChat);
            
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
            return DBChat(id: id!, account: account, jid: c.jid.bareJid, timestamp: Date(), readTill: getReadTill(for: account, with: c.jid.bareJid), lastMessage: getLastMessage(for: account, jid: c.jid.bareJid), unread: 0);
        case let r as Room:
            let params:[String:Any?] = [ "account" : account, "jid" : r.jid.bareJid, "timestamp": NSDate(), "type" : 1, "nickname" : r.nickname, "password" : r.password ];
            let id = try! self.openRoomStmt.insert(params);
            return DBRoom(id: id!, context: r.context, account: account, roomJid: r.roomJid, roomName: nil, nickname: r.nickname, password: r.password, timestamp: Date(), readTill: getReadTill(for: account, with: r.jid.bareJid), lastMessage: getLastMessage(for: account, jid: r.jid.bareJid), unread: 0);
        default:
            return nil;
        }
    }
    
    fileprivate func destroyChat(account: BareJID, chat: DBChatProtocol) {
        let params: [String: Any?] = ["id": chat.id];
        _ = try! self.closeChatStmt.update(params);
        _ = try! self.deleteReadTillStmt.update(["account": account, "jid": chat.jid.bareJid] as [String: Any?]);
    }
    
    var getReadTillStmt: DBStatement;
    
    fileprivate func getReadTill(for account: BareJID, with jid: BareJID) -> Date {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account, "jid": jid];
            return try! self.getReadTillStmt.queryFirstMatching(params, forEachRowUntil: { (cursor) -> Date? in
                return cursor["timestamp"];
            }) ?? Date.distantPast;
        }
    }

    fileprivate func getLastMessage(for account: BareJID, jid: BareJID) -> String? {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account, "jid": jid];
            return try! self.getLastMessageStmt.queryFirstMatching(params) { cursor in
                let encryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
                switch encryption {
                case .decrypted, .none:
                    return cursor["data"];
                default:
                    return encryption.message();
                }
            }
        }
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
            guard self.accountChats[account] == nil else {
                return;
            }
            let chats = try! self.getAllStmt.query(params) { (cursor) -> DBChatProtocol? in
                let id: Int = cursor["id"]!;
                let type:Int = cursor["type"]!;
                let jid: BareJID = cursor["jid"]!;
                let creationTimestamp: Date = cursor["creation_timestamp"]!;
                let lastMessageTimestamp: Date = cursor["timestamp"]!;
                let lastMessageEncryption = MessageEncryption(rawValue: cursor["lastEncryption"] ?? 0) ?? .none;
                let lastMessage: String? = lastMessageEncryption.message() ?? cursor["data"];
                let readTill: Date = cursor["read_till"] ?? Date.distantPast;
                let unread: Int = cursor["unread"]!;
                
                let timestamp = creationTimestamp.compare(lastMessageTimestamp) == .orderedAscending ? lastMessageTimestamp : creationTimestamp;


                switch type {
                case 1:
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
                    let name: String? = cursor["name"];
                    let room = DBRoom(id: id, context: context, account: account, roomJid: jid, roomName: name, nickname: nickname, password: password, timestamp: timestamp, readTill: readTill, lastMessage: lastMessage, unread: unread);
                    if lastMessage != nil {
                        room.lastMessageDate = timestamp;
                    }
                    
                    if let dataStr: String = cursor["options"], let data = dataStr.data(using: .utf8), let options = try? JSONDecoder().decode(RoomOptions.self, from: data) {
                        room.options = options;
                    }
                    return room;
                default:
                    let c = DBChat(id: id, account: account, jid: jid, timestamp: timestamp, readTill: readTill, lastMessage: lastMessage, unread: unread);
                    if let dataStr: String = cursor["options"], let data = dataStr.data(using: .utf8), let options = try? JSONDecoder().decode(ChatOptions.self, from: data) {
                        c.options = options;
                    }
                    return c;
                }
            }
            let accountChats = AccountChats(items: chats);
            self.accountChats[account] = accountChats;
            var unread = 0;
            chats.forEach { item in
                unread = unread + item.unread;
                NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: item);
            }
            if unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount + unread;
            }
        }
    }
    
    func unloadChats(for account: BareJID) {
        dispatcher.async {
            guard let accountChats = self.accountChats.removeValue(forKey: account) else {
                return;
            }
            
            var unread = 0;
            accountChats.items.forEach { item in
                unread = unread + item.unread;
                NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: item);
            }
            if unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount - unread;
            }
        }
    }
        
    func lastMessageTimestamp(for account: BareJID) -> Date {
        return dispatcher.sync {
            return try! self.getLastMessageTimestampForAccountStmt.findFirst(["account": account] as [String: Any?], map: { (cursor) -> Date? in
                return cursor["timestamp"];
            }) ?? Date(timeIntervalSince1970: 0);
        }
    }
    
    open func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, message: String?, state: MessageState, remoteChatState: ChatState? = nil, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                if chat.updateLastMessage(message, timestamp: timestamp, isUnread: state.isUnread) {
                    if state.isUnread /*&& !self.isMuted(chat: chat)*/ {
                        self.unreadMessagesCount = self.unreadMessagesCount + 1;
                    }
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                } else {
                    print("not updated chat for", account, jid, message, timestamp, chat.timestamp, chat.lastMessage);
                }
            }
            completionHandler();
        }
    }
    
    let updateReadTillStmt: DBStatement;

    func markAsRead(for account: BareJID, with jid: BareJID, before: Date, count: Int? = nil, completionHandler: (()->Void)? = nil) {
        dispatcher.async {
            var ts: Date = before;
            if #available(iOS 12.0, *) {
                // we do not have to use workaround..
            } else {
                // workaround for iOS 11
                ts = max(self.getReadTill(for: account, with: jid), before);
                try! self.deleteReadTillStmt.update(["account": account, "jid": jid] as [String: Any?]);
            }
            _ = try! self.updateReadTillStmt.insert(["account": account, "jid": jid, "before": ts] as [String: Any?]);

            if let chat = self.getChat(for: account, with: jid) {
                let unread = chat.unread;
                if chat.markAsRead(before: before, count: count ?? unread) {
                    //if !self.isMuted(chat: chat) {
                        self.unreadMessagesCount = self.unreadMessagesCount - (count ?? unread);
                    //}
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                }
                completionHandler?();
            }
        }
    }
    
    open func updateChatName(for account: BareJID, with jid: BareJID, name: String?) {
        dispatcher.async {
            _ = try? self.updateChatNameStmt.update(name, account, jid);
            if let r = self.getChat(for: account, with: jid) as? DBRoom {
                r.name = name;
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
            _ = try? self.updateMessageDraftStmt.update(draft, account, jid, draft);
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
    var readTill: Date { get }
    var unread: Int { get }
    var timestamp: Date { get }
    var lastMessage: String? { get }
    
    func markAsRead(before: Date, count: Int) -> Bool;

    func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool
    
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

public enum ConversationNotification: String {
    case none
    case mention
    case always
}

public protocol ChatOptionsProtocol {
    
    var notifications: ConversationNotification { get }
    
}

public struct ChatOptions: Codable, ChatOptionsProtocol {
    
    var encryption: ChatEncryption?;
    public var notifications: ConversationNotification = .always;
    
    init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        if let val = try container.decodeIfPresent(String.self, forKey: .encryption) {
            encryption = ChatEncryption(rawValue: val);
        }
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .always;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if encryption != nil {
            try container.encode(encryption!.rawValue, forKey: .encryption);
        }
        if notifications != .always {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case encryption = "encrypt"
        case notifications = "notifications";
    }

}

class DBChat: Chat, DBChatProtocol {

    let id: Int;
    let account: BareJID;
    var timestamp: Date;
    var readTill: Date;
    var lastMessage: String? = nil;
    var unread: Int;
    fileprivate(set) var options: ChatOptions = ChatOptions();
    
    override var jid: JID {
        get {
            return super.jid;
        }
        set {
            super.jid = newValue.withoutResource;
        }
    }
    
    init(id: Int, account: BareJID, jid: BareJID, timestamp: Date, readTill: Date, lastMessage: String?, unread: Int) {
        self.id = id;
        self.account = account;
        self.timestamp = timestamp;
        self.lastMessage = lastMessage;
        self.unread = unread;
        self.readTill = readTill;
        super.init(jid: JID(jid), thread: nil);
    }
 
    func markAsRead(before: Date, count: Int) -> Bool {
        self.readTill = before;
        guard unread > 0 else {
            return false;
        }
        unread = max(unread - count, 0);
        return true
    }

    func modifyOptions(_ fn: @escaping (inout ChatOptions)->Void, completionHandler: (()->Void)? = nil) {
        DispatchQueue.main.async {
            var options = self.options;
            fn(&options);
            DBChatStore.instance.updateOptions(for: self.account, jid: self.jid.bareJid, options: options, completionHandler: completionHandler);
        }
    }
    
    func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool {
        if isUnread {
            unread = unread + 1;
        }
        guard self.lastMessage == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
            return isUnread;
        }
        if message != nil {
            self.lastMessage = message;
            self.timestamp = timestamp;
        }
        return true;
    }

}

class DBRoom: Room, DBChatProtocol {
    
    let id: Int;
    let account: BareJID;
    var timestamp: Date;
    var lastMessage: String? = nil;
    var subject: String?;
    var readTill: Date;
    var unread: Int;
    var name: String? = nil;
    fileprivate(set) var options: RoomOptions = RoomOptions();
    
    init(id: Int, context: Context, account: BareJID, roomJid: BareJID, roomName: String?, nickname: String, password: String?, timestamp: Date, readTill: Date, lastMessage: String?, unread: Int) {
        self.id = id;
        self.account = account;
        self.timestamp = timestamp;
        self.lastMessage = lastMessage;
        self.name = roomName;
        self.readTill = readTill;
        self.unread = unread;
        super.init(context: context, roomJid: roomJid, nickname: nickname);
        self.password = password;
    }
    
    func markAsRead(before: Date, count: Int) -> Bool {
        self.readTill = before;
        guard unread > 0 else {
            return false;
        }
        unread = max(unread - count, 0);
        return true
    }

    func modifyOptions(_ fn: @escaping (inout RoomOptions)->Void, completionHandler: (()->Void)? = nil) {
        DispatchQueue.main.async {
            var options = self.options;
            fn(&options);
            DBChatStore.instance.updateOptions(for: self.account, jid: self.roomJid, options: options, completionHandler: completionHandler);
        }
    }
    
    func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool {
        if isUnread {
            unread = unread + 1;
        }
        guard self.lastMessage == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
            return isUnread;
        }
        if message != nil {
            self.lastMessage = message;
            self.timestamp = timestamp;
        }
        return true;
    }
}

public enum ChatEncryption: String {
    case none = "none";
    case omemo = "omemo";
}
