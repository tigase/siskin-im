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

open class DBChatStoreWrapper: ChatStore {
    
    fileprivate let cache: NSCache<NSString, AnyObject>?;
    fileprivate let store: DBChatStore;
    fileprivate let sessionObject: SessionObject;
    
    open var count:Int {
        return store.count(for: sessionObject);
    }
    
    open var items:[ChatProtocol] {
        return store.getAll(for: sessionObject);
    }
    
    open let dispatcher: QueueDispatcher;
        
    public init(sessionObject:SessionObject, store:DBChatStore, useCache: Bool = true) {
        self.sessionObject = sessionObject;
        self.store = store;
        self.cache = useCache ? NSCache() : nil;
        self.cache?.countLimit = 100;
        self.cache?.totalCostLimit = 512 * 1024;
        self.dispatcher = store.dispatcher;
    }
    
    open func getChat<T: AnyObject>(with jid: BareJID, filter: @escaping (T) -> Bool) -> T? {
        return self.dispatcher.sync {
            if cache != nil {
                let key = createKey(jid: jid);
                if let chats = self.cache!.object(forKey: key as NSString) as? [T] {
                    for chat in chats {
                        if filter(chat) {
                            return chat;
                        }
                    }
                    return nil;
                }
                
                let chats: [T] = self.store.getAll(for: self.sessionObject, with: jid);
                guard !chats.isEmpty else {
                    return nil;
                }
                
                self.cache?.setObject(chats as NSArray, forKey: key as NSString);
                
                for chat in chats {
                    if filter(chat) {
                        return chat;
                    }
                }
                return nil;
            } else {
               return store.get(for: sessionObject, with: jid, filter: filter);
            }
        }
    }
    
    open func getAllChats<T>() -> [T] {
        return store.getAll(for: sessionObject);
    }
    
    open func isFor(jid: BareJID) -> Bool {
        return store.isFor(sessionObject, jid: jid);
    }
    
    open func open<T: AnyObject>(chat:ChatProtocol) -> T? {
        return self.dispatcher.sync(flags: .barrier) {
            let dbChat: T? = store.open(for: sessionObject, chat: chat);
            if dbChat != nil && cache != nil {
                let key = self.createKey(jid: chat.jid.bareJid);
                var chats = (self.cache!.object(forKey: key as NSString) as? [T]) ?? [];
                chats.append(dbChat!);
                self.cache?.setObject(chats as NSArray, forKey: key as NSString);
            }
            return dbChat;
        }
    }
    
    open func close(chat:ChatProtocol) -> Bool {
        return self.dispatcher.sync(flags: .barrier) {
            let closed = store.close(chat: chat);
            if closed && cache != nil {
                self.cache?.removeObject(forKey: self.createKey(jid: chat.jid.bareJid) as NSString);
            }
            return closed;
        }
    }
    
    fileprivate func createKey(jid: BareJID) -> String {
        return jid.stringValue.lowercased();
    }
}

open class DBChatStore {
    
    fileprivate static let CHATS_GET = "SELECT id, type, thread_id, resource, nickname, password, timestamp FROM chats WHERE account = :account AND jid = :jid";
    fileprivate static let CHATS_LIST = "SELECT id, jid, type, thread_id, resource, nickname, password, timestamp FROM chats WHERE account = :account";
    fileprivate static let CHAT_IS = "SELECT count(id) as count FROM chats WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_OPEN = "INSERT INTO chats (account, jid, timestamp, type, resource, thread_id) VALUES (:account, :jid, :timestamp, :type, :resource, :thread)";
    fileprivate static let ROOM_OPEN = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    fileprivate static let CHAT_CLOSE = "DELETE FROM chats WHERE id = :id";
    fileprivate static let CHATS_COUNT = "SELECT count(id) as count FROM chats WHERE account = :account";
    
    fileprivate let dbConnection:DBConnection;
    
    fileprivate lazy var getStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHATS_GET);
    fileprivate lazy var getAllStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHATS_LIST);
    fileprivate lazy var isForStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHAT_IS);
    fileprivate lazy var openChatStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHAT_OPEN);
    fileprivate lazy var openRoomStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.ROOM_OPEN);
    fileprivate lazy var closeChatStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHAT_CLOSE);
    fileprivate lazy var countStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatStore.CHATS_COUNT);
    
    open let dispatcher: QueueDispatcher;
    
    public init(dbConnection:DBConnection, dispatcher: QueueDispatcher? = nil) {
        self.dbConnection = dbConnection;
        self.dispatcher = dispatcher ?? QueueDispatcher(queue: DispatchQueue(label: "db_chat_store_queue", attributes: DispatchQueue.Attributes.concurrent), queueTag: DispatchSpecificKey<DispatchQueue?>());

        NotificationCenter.default.addObserver(self, selector: #selector(DBChatStore.accountRemoved), name: NSNotification.Name(rawValue: "accountRemoved"), object: nil);
    }
    
    open func count(for sessionObject: SessionObject) -> Int {
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid?.description ];
        do {
            return try countStmt.scalar(params) ?? 0;
        } catch _ {
            
        }
        return 0;
    }
    
    open func get<T>(for sessionObject: SessionObject, with jid: BareJID, filter: ((T) -> Bool)?) -> T? {
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : jid ];
        let context = getContext(sessionObject)!;
        return dispatcher.sync {
            return try! self.getStmt.queryFirstMatching(params) { (cursor) -> T? in
                let type:Int = cursor["type"]!;
                switch type {
                case 1:
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
                return nil;
            }
        }
    }
    
    open func getAll<T>(for sessionObject: SessionObject, with forJid: BareJID) -> [T] {
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : forJid ];
        let context = getContext(sessionObject)!;
        return dispatcher.sync {
            try! self.getStmt.query(params) { (cursor) -> T? in
                let type:Int = cursor["type"]!;
                switch type {
                case 1:
                    let jid: BareJID = forJid;
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
                    let jid = JID(forJid, resource: resource);
                    let c = DBChat(jid: jid, thread: thread);
                    c.id = cursor["id"];
                    if let chat = c as? T {
                        return chat;
                    }
                }
                return nil;
            }
        }
    }
    
    open func getAll<T>(for sessionObject:SessionObject) -> [T] {
        let context = getContext(sessionObject);
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid ];
        return dispatcher.sync {
            return try! self.getAllStmt.query(params) { (cursor) -> T? in
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
                        return r;
                    }
                    break;
                default:
                    let resource:String? = cursor["resource"];
                    let thread:String? = cursor["thread_id"];
                    let bareJid:BareJID = cursor["jid"]!;
                    let jid = JID(bareJid, resource: resource);
                    if let c = DBChat(jid: jid, thread: thread) as? T {
                        (c as! DBChat).id = id;
                        return c;
                    }
                }
                return nil;
            }
        }
    }
    
    open func isFor(_ sessionObject:SessionObject, jid:BareJID) -> Bool {
        return dispatcher.sync {
            let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : jid ];
            let count = try! self.isForStmt.scalar(params, columnName: "count") ?? 0;
            
            return count > 0;
        }
    }
    
    open func open<T>(for sessionObject:SessionObject, chat:ChatProtocol) -> T? {
        return dispatcher.sync(flags: .barrier) {
            let current:ChatProtocol? = get(for: sessionObject, with: chat.jid.bareJid, filter: nil);
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
    }
    
    open func close(chat:ChatProtocol) -> Bool {
        return dispatcher.sync(flags: .barrier) {
            if let id = chat.id {
                let params:[String:Any?] = [ "id" : id ];
                return try! closeChatStmt.update(params) > 0;
            }
            return false;
        }
    }
    
    @objc open func accountRemoved(_ notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            _ = try! dbConnection.prepareStatement("DELETE FROM chats WHERE account = ?").update(accountStr);
        }
    }
    
    fileprivate func getContext(_ sessionObject: SessionObject) -> Context? {
        return sessionObject.context;
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
