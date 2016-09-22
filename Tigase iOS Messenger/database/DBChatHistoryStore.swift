//
// DBChatHistoryStore.swift
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
import TigaseSwift

open class DBChatHistoryStore: Logger, EventHandler {
    
    open static let MESSAGE_NEW = Notification.Name("messengerMessageNew");
    open static let CHAT_ITEMS_UPDATED = Notification.Name("messengerChatUpdated");
    
    fileprivate static let CHAT_MSG_APPEND = "INSERT INTO chat_history (account, jid, author_jid, author_nickname, timestamp, item_type, data, stanza_id, state) VALUES (:account, :jid, :author_jid, :author_nickname, :timestamp, :item_type, :data, :stanza_id, :state)";
    fileprivate static let CHAT_MSGS_COUNT = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_MSGS_COUNT_UNREAD_CHATS = "select count(1) FROM (SELECT account, jid FROM chat_history WHERE state = \(State.incoming_unread.rawValue) GROUP BY account, jid) as x";
    fileprivate static let CHAT_MSGS_DELETE = "DELETE FROM chat_history WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_MSGS_GET = "SELECT id, author_jid, author_nickname, timestamp, item_type, data, state FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp LIMIT :limit OFFSET :offset"
    fileprivate static let CHAT_MSGS_MARK_AS_READ = "UPDATE chat_history SET state = \(State.incoming.rawValue) WHERE account = :account AND jid = :jid AND state = \(State.incoming_unread.rawValue)";
    fileprivate static let MSG_ALREADY_ADDED = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND data = :data AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (:author_jid is null OR author_jid = :author_jid) AND (:author_nickname is null OR author_nickname = :author_nickname)";
    
    fileprivate let dbConnection:DBConnection;
    
    fileprivate lazy var msgAppendStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_APPEND);
    fileprivate lazy var msgsCountStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT);
    fileprivate lazy var msgsDeleteStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_DELETE);
    fileprivate lazy var msgsCountUnreadChatsStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT_UNREAD_CHATS);
    //private lazy var msgsGetStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_GET);
    fileprivate lazy var msgsMarkAsReadStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_MARK_AS_READ);
    fileprivate lazy var msgAlreadyAddedStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.MSG_ALREADY_ADDED);
    fileprivate lazy var chatUpdateTimestamp: DBStatement! = try? self.dbConnection.prepareStatement("UPDATE chats SET timestamp = :timestamp WHERE account = :account AND jid = :jid");
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        super.init();
        NotificationCenter.default.addObserver(self, selector: #selector(DBChatHistoryStore.accountRemoved), name: NSNotification.Name(rawValue: "accountRemoved"), object: nil);
    }
    
    open func appendMessage(for sessionObject: SessionObject, message: Message, carbonAction: MessageCarbonsModule.Action? = nil) {
        let body = message.body;
        // for now we support only messages with body
        guard body != nil else {
            return;
        }
        
        let incoming = message.from != nil && message.from != ResourceBinderModule.getBindedJid(sessionObject);
        
        let account = sessionObject.userBareJid!;
        let jid = incoming ? message.from?.bareJid : message.to?.bareJid
        let author = incoming ? message.from?.bareJid : account;
        let timestamp = message.delay?.stamp ?? Date();
        
        if appendEntry(for: account, jid: jid!, incoming: incoming, authorJid: author, data: body!, timestamp: timestamp, id: message.id) {

            var userInfo:[AnyHashable: Any] = ["account": account, "sender": jid!, "incoming": incoming, "timestamp": timestamp] ;
            if carbonAction != nil {
                userInfo["carbonAction"] = carbonAction!.rawValue;
            }
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: nil, userInfo: userInfo);
        }
    }
    
    fileprivate func appendMucMessage(event e: MucModule.MessageReceivedEvent) {
        let body = e.message.body;
        guard body != nil else {
            return;
        }
        
        let account = e.sessionObject.userBareJid!;
        let authorJid: BareJID? = e.nickname == nil ? nil : e.room.presences[e.nickname!]?.jid?.bareJid;
        
        if appendEntry(for: account, jid: e.room.roomJid, incoming: true, authorJid: authorJid, authorNickname: e.nickname, data: body!, timestamp: e.timestamp, id: e.message.id) {

            var userInfo:[AnyHashable: Any] = ["account": account, "sender": e.room.roomJid, "incoming": true, "timestamp": e.timestamp, "type": "muc", "body": body!] ;
            if e.nickname != nil {
                userInfo["senderName"] = e.nickname!;
            }
            userInfo["roomNickname"] = e.room.nickname;
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: nil, userInfo: userInfo);
        }
    }
    
    fileprivate func appendEntry(for account: BareJID, jid: BareJID, incoming: Bool, authorJid: BareJID?, authorNickname: String? = nil, itemType: ItemType = ItemType.message, data: String, timestamp: Date, id: String?) -> Bool {
        guard !isEntryAlreadyAdded(for: account, jid: jid, authorJid: authorJid, itemType: itemType, data: data, timestamp: timestamp, id: id) else {
            return false;
        }
        
        let state = incoming ? State.incoming_unread : State.outgoing;
        let params:[String:Any?] = ["account" : account, "jid" : jid, "author_jid" : authorJid, "author_nickname": authorNickname, "timestamp": timestamp, "item_type": itemType.rawValue, "data": data, "state": state.rawValue, "stanza_id": id]
        dbConnection.dispatch_async_db_queue() {
            _ = try! self.msgAppendStmt.insert(params);
            let cu_params:[String:Any?] = ["account" : account, "jid" : jid, "timestamp" : timestamp ];
            _ = try! self.chatUpdateTimestamp.execute(cu_params);
        }
        return true;
    }
    
    fileprivate func isEntryAlreadyAdded(for account: BareJID, jid: BareJID, authorJid: BareJID?, authorNickname: String? = nil, itemType: ItemType, data: String, timestamp: Date, id: String?) -> Bool {
        
        let range = id == nil ? 5.0 : 60.0;
        let ts_from = timestamp.addingTimeInterval(-60 * range);
        let ts_to = timestamp.addingTimeInterval(60 * range);
        
        let params:[String:Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": itemType.rawValue, "data": data, "stanza_id": id, "author_jid": authorJid, "author_nickname": authorNickname];
        return try! msgAlreadyAddedStmt.scalar(params) != 0;
    }
    
    open func countMessages(for account:BareJID, with jid:BareJID) -> Int {
        let params:[String:Any?] = ["account":account, "jid":jid];
        return try! msgsCountStmt.scalar(params) ?? 0;
    }
    
    open func forEachMessage(stmt: DBStatement, account:BareJID, jid:BareJID, limit:Int, offset: Int, forEach: (_ cursor:DBCursor)->Void) {
        let params:[String:Any?] = ["account":account, "jid":jid, "limit": limit, "offset": offset];
        try! stmt.query(params, forEachRow: forEach);
    }
    
    open func getMessagesStatementForAccountAndJid() -> DBStatement {
        return try! self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_GET);
    }
    
    open func handle(event:Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            appendMessage(for: e.sessionObject, message: e.message);
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            appendMessage(for: e.sessionObject, message: e.message, carbonAction: e.action);
        case let e as MucModule.MessageReceivedEvent:
            appendMucMessage(event: e);
        default:
            log("received unsupported event", event);
        }
    }
    
    open func countUnreadChats() -> Int {
        return try! msgsCountUnreadChatsStmt.scalar() ?? 0;
    }
    
    open func markAsRead(for account: BareJID, with jid: BareJID) {
        dbConnection.dispatch_async_db_queue() {
            let params:[String:Any?] = ["account":account, "jid":jid];
            let updatedRecords = try! self.msgsMarkAsReadStmt.update(params);
            if updatedRecords > 0 {
                DispatchQueue.global(qos: .default).async() {
                    self.chatItemsChanged(for: account, with: jid);
                }
            }
        }
    }
    
    open func deleteMessages(for account: BareJID, with jid: BareJID) {
        let params:[String:Any?] = ["account":account, "jid":jid];
        dbConnection.dispatch_async_db_queue() {
            _ = try! self.msgsDeleteStmt.execute(params);
        }
    }
    
    @objc open func accountRemoved(_ notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            _ = try! dbConnection.prepareStatement("DELETE FROM chat_history WHERE account = ?").execute(accountStr);
        }
    }
    
    fileprivate func chatItemsChanged(for account: BareJID, with jid: BareJID) {
        let userInfo:[AnyHashable: Any] = ["account":account, "jid":jid];
        NotificationCenter.default.post(name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil, userInfo: userInfo);
    }
    
    public enum State:Int {
        case incoming = 0
        case outgoing = 1
        case incoming_unread = 2
        case outgoing_unsent = 3
    }
    
    public enum ItemType:Int {
        case message = 0
    }
}
