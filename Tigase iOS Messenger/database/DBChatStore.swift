//
// DBChatStore.swift
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

import UIKit
import TigaseSwift

public class DBChatStoreWrapper: ChatStore {
    
    private let cache: NSCache?;
    private let store: DBChatStore;
    private let sessionObject: SessionObject;
    
    private var queue: dispatch_queue_t?;
    
    public var count:Int {
        return store.count(sessionObject);
    }
    
    public var items:[ChatProtocol] {
        return store.getAll(sessionObject);
    }
    
    public init(sessionObject:SessionObject, store:DBChatStore, useCache: Bool = true) {
        self.sessionObject = sessionObject;
        self.store = store;
        self.cache = useCache ? NSCache() : nil;
        self.cache?.countLimit = 100;
        self.cache?.totalCostLimit = 512 * 1024;
        self.queue = useCache ? dispatch_queue_create("chat_store_queue", DISPATCH_QUEUE_SERIAL) : nil;
    }
    
    public func get<T: AnyObject>(jid: BareJID, filter: (T) -> Bool) -> T? {
        var item: T?;
        if cache != nil {
            dispatch_sync(queue!) {
                if let chats = self.cache!.objectForKey(jid.stringValue) as? [T] {
                    for chat in chats {
                        if filter(chat) {
                            item = chat;
                            return;
                        }
                    }
                    return;
                }
                
                if let chats: [T] = self.store.getAll(self.sessionObject, forJid: jid) {
                    guard !chats.isEmpty else {
                        return;
                    }
                    
                    self.cache?.setObject(chats, forKey: jid.stringValue);
                    
                    for chat in chats {
                        if filter(chat) {
                            item = chat;
                            return;
                        }
                    }
                }
            }
            return item;
        }
        return store.get(sessionObject, jid: jid, filter: filter);
    }
    
    public func getAll<T>() -> [T] {
        return store.getAll(sessionObject);
    }
    
    public func isFor(jid: BareJID) -> Bool {
        return store.isFor(sessionObject, jid: jid);
    }
    
    public func open<T: AnyObject>(chat:ChatProtocol) -> T? {
        let dbChat: T? = store.open(sessionObject, chat: chat);
        if dbChat != nil && cache != nil {
            dispatch_sync(queue!) {
                var chats = (self.cache!.objectForKey(chat.jid.bareJid.stringValue) as? [T]) ?? [];
                chats.append(dbChat!);
                self.cache?.setObject(chats, forKey: chat.jid.bareJid.stringValue);
            }
        }
        return dbChat;
    }
    
    public func close(chat:ChatProtocol) -> Bool {
        let closed = store.close(chat);
        if closed && cache != nil {
            dispatch_sync(queue!) {
                self.cache?.removeObjectForKey(chat.jid.bareJid.stringValue);
            }
        }
        return closed;
    }
}

public class DBChatStore: LocalQueueDispatcher {
    
    private static let CHATS_GET = "SELECT id, type, thread_id, resource, timestamp FROM chats WHERE account = :account AND jid = :jid";
    private static let CHATS_LIST = "SELECT id, jid, type, thread_id, resource, nickname, password, timestamp FROM chats WHERE account = :account";
    private static let CHAT_IS = "SELECT count(id) as count FROM chats WHERE account = :account AND jid = :jid";
    private static let CHAT_OPEN = "INSERT INTO chats (account, jid, timestamp, type, resource, thread_id) VALUES (:account, :jid, :timestamp, :type, :resource, :thread)";
    private static let ROOM_OPEN = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    private static let CHAT_CLOSE = "DELETE FROM chats WHERE id = :id";
    private static let CHATS_COUNT = "SELECT count(id) as count FROM chats WHERE account = :account";
    
    private let dbConnection:DBConnection;
    public let queue: dispatch_queue_t = dispatch_queue_create("db_chat_store_queue", DISPATCH_QUEUE_SERIAL);
    public let queueTag: UnsafeMutablePointer<Void>;
    
    private lazy var getStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHATS_GET);
    private lazy var getAllStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHATS_LIST);
    private lazy var isForStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHAT_IS);
    private lazy var openChatStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHAT_OPEN);
    private lazy var openRoomStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.ROOM_OPEN);
    private lazy var closeChatStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHAT_CLOSE);
    private lazy var countStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHATS_COUNT);
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        self.queueTag = UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self.queue).toOpaque());
        dispatch_queue_set_specific(queue, queueTag, queueTag, nil);

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(DBChatStore.accountRemoved), name: "accountRemoved", object: nil);
    }
    
    public func count(sessionObject: SessionObject) -> Int {
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid?.description ];
        do {
            return try countStmt.scalar(params) ?? 0;
        } catch _ {
            
        }
        return 0;
    }
    
    public func get<T>(sessionObject: SessionObject, jid: BareJID, filter: ((T) -> Bool)?) -> T? {
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : jid ];
        let context = getContext(sessionObject)!;
        return dispatch_sync_with_result_local_queue() {
            if let cursor = try! self.getStmt.query(params) {
                repeat {
                    let type:Int = cursor["type"]!;
                    switch type {
                    case 1:
                        let jid: BareJID = cursor["jid"]!;
                        let nickname: String = cursor["nickname"]!;
                        let password: String? = cursor["password"];
                        if let r = DBRoom(context: context, roomJid: jid, nickname: nickname) as? T {
                            (r as! DBRoom).id = cursor["id"];
                            (r as! DBRoom).password = password;
                            (r as! DBRoom).lastMessageDate = cursor["timestamp"];
                            return r;
                        }
                        break;
                    default:
                        let resource:String? = cursor["resource"];
                        let thread:String? = cursor["thread_id"];
                        let jid = JID(jid, resource: resource);
                        let c = DBChat(jid: jid, thread: thread);
                        c.id = cursor["id"];
                        if let chat = c as? T {
                            if filter == nil || filter!(chat) {
                                return chat;
                            }
                        }
                    }
                } while cursor.next()
            }
            return nil;
        }
    }
    
    public func getAll<T>(sessionObject: SessionObject, forJid: BareJID) -> [T] {
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : forJid ];
        let context = getContext(sessionObject)!;
        var result = [T]();
        dispatch_sync_local_queue() {
            try! self.getStmt.query(params) { (cursor) -> Void in
                let type:Int = cursor["type"]!;
                switch type {
                case 1:
                    let jid: BareJID = cursor["jid"]!;
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
                    if let r = DBRoom(context: context, roomJid: jid, nickname: nickname) as? T {
                        (r as! DBRoom).id = cursor["id"];
                        (r as! DBRoom).password = password;
                        (r as! DBRoom).lastMessageDate = cursor["timestamp"];
                        result.append(r);
                    }
                    break;
                default:
                    let resource:String? = cursor["resource"];
                    let thread:String? = cursor["thread_id"];
                    let jid = JID(forJid, resource: resource);
                    let c = DBChat(jid: jid, thread: thread);
                    c.id = cursor["id"];
                    if let chat = c as? T {
                        result.append(chat);
                    }
                }
            }
        }
        return result;
    }
    
    public func getAll<T>(sessionObject:SessionObject) -> [T] {
        var result = [T]();
        let context = getContext(sessionObject);
        dispatch_sync_local_queue() {
            let params:[String:Any?] = [ "account" : sessionObject.userBareJid ];
            try! self.getAllStmt.query(params) { (cursor) -> Bool in
                let type:Int = cursor["type"]!;
                let id: Int? = cursor["id"];
                switch type {
                case 1:
                    let jid: BareJID = cursor["jid"]!;
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
                    if let r = DBRoom(context: context!, roomJid: jid, nickname: nickname) as? T {
                        (r as! DBRoom).id = id;
                        (r as! DBRoom).password = password;
                        (r as! DBRoom).lastMessageDate = cursor["timestamp"];
                        result.append(r);
                    }
                    break;
                default:
                    let resource:String? = cursor["resource"];
                    let thread:String? = cursor["thread_id"];
                    let bareJid:BareJID = cursor["jid"]!;
                    let jid = JID(bareJid, resource: resource);
                    if let c = DBChat(jid: jid, thread: thread) as? T {
                        (c as! DBChat).id = id;
                        result.append(c);
                    }
                }
                return true;
            }
        }
        return result;
    }
    
    public func isFor(sessionObject:SessionObject, jid:BareJID) -> Bool {
        return dispatch_sync_with_result_local_queue() {
            let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : jid ];
            let cursor = try! self.isForStmt.query(params)!;
            
            let count:Int = cursor["count"] ?? 0;
            return count > 0;
        }
    }
    
    public func open<T>(sessionObject:SessionObject, chat:ChatProtocol) -> T? {
        let current:ChatProtocol? = get(sessionObject, jid: chat.jid.bareJid, filter: nil);
        if current?.allowFullJid == false {
            return current as? T;
        }
        
        switch chat {
        case let c as Chat:
            let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : c.jid.bareJid, "timestamp": NSDate(), "type" : 0, "resource" : c.jid.resource, "thread" : c.thread ];
            let id = try! self.openChatStmt.insert(params);
            let dbChat = DBChat(jid: c.jid, thread: c.thread);
            dbChat.id = id;
            return dbChat as? T;
        case let r as Room:
            let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : r.jid.bareJid, "timestamp": NSDate(), "type" : 1, "nickname" : r.nickname, "password" : r.password ];
            let id = try! self.openRoomStmt.insert(params);
            let dbRoom = DBRoom(context: r.context, roomJid: r.roomJid, nickname: r.nickname);
            dbRoom.password = r.password;
            dbRoom.id = id;
            return dbRoom as? T;
        default:
            return nil;
        }
    }
    
    public func close(chat:ChatProtocol) -> Bool {
        if let id = chat.id {
            let params:[String:Any?] = [ "id" : id ];
            return try! closeChatStmt.update(params) > 0;
        }
        return false;
    }
    
    @objc public func accountRemoved(notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            try! dbConnection.prepareStatement("DELETE FROM chats WHERE account = ?").execute(accountStr);
        }
    }
    
    private func getContext(sessionObject: SessionObject) -> Context? {
        return (UIApplication.sharedApplication().delegate as? AppDelegate)?.xmppService.getClient(sessionObject.userBareJid!)?.context;
    }
}

extension ChatProtocol {
    
    var id:Int? {
        switch self {
        case let c as DBChat:
            return c.id;
        case let r as DBRoom:
            return r.id;
        default:
            return nil;
        }
    }
    
}

class DBChat: Chat {
    
    var id:Int? = nil;
    
}
