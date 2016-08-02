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

public class DBChatHistoryStore: Logger, EventHandler {
    
    public static let MESSAGE_NEW = "messengerMessageNew";
    public static let CHAT_ITEMS_UPDATED = "messengerChatUpdated";
    
    private static let CHAT_MSG_APPEND = "INSERT INTO chat_history (account, jid, author_jid, author_nickname, timestamp, item_type, data, stanza_id, state) VALUES (:account, :jid, :author_jid, :author_nickname, :timestamp, :item_type, :data, :stanza_id, :state)";
    private static let CHAT_MSGS_COUNT = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid";
    private static let CHAT_MSGS_COUNT_UNREAD_CHATS = "select count(1) FROM (SELECT account, jid FROM chat_history WHERE state = \(State.incoming_unread.rawValue) GROUP BY account, jid) as x";
    private static let CHAT_MSGS_DELETE = "DELETE FROM chat_history WHERE account = :account AND jid = :jid";
    private static let CHAT_MSGS_GET = "SELECT id, author_jid, author_nickname, timestamp, item_type, data, state FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp LIMIT :limit OFFSET :offset"
    private static let CHAT_MSGS_MARK_AS_READ = "UPDATE chat_history SET state = \(State.incoming.rawValue) WHERE account = :account AND jid = :jid AND state = \(State.incoming_unread.rawValue)";
    private static let MSG_ALREADY_ADDED = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND data = :data AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (:author_jid is null OR author_jid = :author_jid) AND (:author_nickname is null OR author_nickname = :author_nickname)";
    
    private let dbConnection:DBConnection;
    
    private lazy var msgAppendStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_APPEND);
    private lazy var msgsCountStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT);
    private lazy var msgsDeleteStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_DELETE);
    private lazy var msgsCountUnreadChatsStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT_UNREAD_CHATS);
    //private lazy var msgsGetStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_GET);
    private lazy var msgsMarkAsReadStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_MARK_AS_READ);
    private lazy var msgAlreadyAddedStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.MSG_ALREADY_ADDED);
    private lazy var chatUpdateTimestamp: DBStatement! = try? self.dbConnection.prepareStatement("UPDATE chats SET timestamp = :timestamp WHERE account = :account AND jid = :jid");
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        super.init();
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(DBChatHistoryStore.accountRemoved), name: "accountRemoved", object: nil);
    }
    
    public func appendMessage(account:BareJID, message: Message, carbonAction: MessageCarbonsModule.Action? = nil) {
        let body = message.body;
        // for now we support only messages with body
        guard body != nil else {
            return;
        }
        
        let incoming = message.from != nil && message.from?.bareJid.stringValue != account.stringValue;
        let jid = incoming ? message.from?.bareJid : message.to?.bareJid
        let author = incoming ? message.from?.bareJid : account;
        let timestamp = message.delay?.stamp ?? NSDate();
        
        if appendEntry(account, jid: jid!, incoming: incoming, authorJid: author, data: body!, timestamp: timestamp, id: message.id) {

            var userInfo:[NSObject:AnyObject] = ["account": account, "sender": jid!, "incoming": incoming, "timestamp": timestamp] ;
            if carbonAction != nil {
                userInfo["carbonAction"] = carbonAction!.rawValue;
            }
            NSNotificationCenter.defaultCenter().postNotification(NSNotification(name: DBChatHistoryStore.MESSAGE_NEW, object: nil, userInfo: userInfo));
        }
    }
    
    private func appendMucMessage(e: MucModule.MessageReceivedEvent) {
        let body = e.message.body;
        guard body != nil else {
            return;
        }
        
        let account = e.sessionObject.userBareJid!;
        let authorJid: BareJID? = e.nickname == nil ? nil : e.room.presences[e.nickname!]?.jid?.bareJid;
        
        if appendEntry(account, jid: e.room.roomJid, incoming: true, authorJid: authorJid, authorNickname: e.nickname, data: body!, timestamp: e.timestamp, id: e.message.id) {

            var userInfo:[NSObject:AnyObject] = ["account": account, "sender": e.room.roomJid, "incoming": true, "timestamp": e.timestamp, "type": "muc", "body": body!] ;
            if e.nickname != nil {
                userInfo["senderName"] = e.nickname!;
            }
            userInfo["roomNickname"] = e.room.nickname;
            NSNotificationCenter.defaultCenter().postNotification(NSNotification(name: DBChatHistoryStore.MESSAGE_NEW, object: nil, userInfo: userInfo));
        }
    }
    
    private func appendEntry(account: BareJID, jid: BareJID, incoming: Bool, authorJid: BareJID?, authorNickname: String? = nil, itemType: ItemType = ItemType.message, data: String, timestamp: NSDate, id: String?) -> Bool {
        guard !isEntryAlreadyAdded(account, jid: jid, authorJid: authorJid, itemType: itemType, data: data, timestamp: timestamp, id: id) else {
            return false;
        }
        
        let state = incoming ? State.incoming_unread : State.outgoing;
        let params:[String:Any?] = ["account" : account, "jid" : jid, "author_jid" : authorJid, "author_nickname": authorNickname, "timestamp": timestamp, "item_type": itemType.rawValue, "data": data, "state": state.rawValue, "stanza_id": id]
        dbConnection.dispatch_async_db_queue() {
            _ = try! self.msgAppendStmt.insert(params);
            let cu_params:[String:Any?] = ["account" : account, "jid" : jid, "timestamp" : timestamp ];
            try! self.chatUpdateTimestamp.execute(cu_params);
        }
        return true;
    }
    
    private func isEntryAlreadyAdded(account: BareJID, jid: BareJID, authorJid: BareJID?, authorNickname: String? = nil, itemType: ItemType, data: String, timestamp: NSDate, id: String?) -> Bool {
        
        let range = id == nil ? 5.0 : 60.0;
        let ts_from = timestamp.dateByAddingTimeInterval(-60 * range);
        let ts_to = timestamp.dateByAddingTimeInterval(60 * range);
        
        let params:[String:Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": itemType.rawValue, "data": data, "stanza_id": id, "author_jid": authorJid, "author_nickname": authorNickname];
        return try! msgAlreadyAddedStmt.scalar(params) != 0;
    }
    
    public func countMessages(account:BareJID, jid:BareJID) -> Int {
        let params:[String:Any?] = ["account":account, "jid":jid];
        return try! msgsCountStmt.scalar(params) ?? 0;
    }
    
    public func forEachMessage(stmt: DBStatement, account:BareJID, jid:BareJID, limit:Int, offset: Int, forEach: (cursor:DBCursor)->Void) {
        let params:[String:Any?] = ["account":account, "jid":jid, "limit": limit, "offset": offset];
        try! stmt.query(params, forEachRow: forEach);
    }
    
    public func getMessagesStatementForAccountAndJid() -> DBStatement {
        return try! self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_GET);
    }
    
    public func handleEvent(event:Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            appendMessage(e.sessionObject.userBareJid!, message: e.message);
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            appendMessage(e.sessionObject.userBareJid!, message: e.message, carbonAction: e.action);
        case let e as MucModule.MessageReceivedEvent:
            appendMucMessage(e);
        default:
            log("received unsupported event", event);
        }
    }
    
    public func countUnreadChats() -> Int {
        return try! msgsCountUnreadChatsStmt.scalar() ?? 0;
    }
    
    public func markAsRead(account: BareJID, jid: BareJID) {
        dbConnection.dispatch_async_db_queue() {
            let params:[String:Any?] = ["account":account, "jid":jid];
            let updatedRecords = try! self.msgsMarkAsReadStmt.update(params);
            if updatedRecords > 0 {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
                    self.chatItemsChanged(account, jid: jid);
                }
            }
        }
    }
    
    public func deleteMessages(account: BareJID, jid: BareJID) {
        let params:[String:Any?] = ["account":account, "jid":jid];
        dbConnection.dispatch_async_db_queue() {
            try! self.msgsDeleteStmt.execute(params);
        }
    }
    
    @objc public func accountRemoved(notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            try! dbConnection.prepareStatement("DELETE FROM chat_history WHERE account = ?").execute(accountStr);
        }
    }
    
    private func chatItemsChanged(account: BareJID, jid: BareJID) {
        let userInfo:[NSObject:AnyObject] = ["account":account, "jid":jid];
        NSNotificationCenter.defaultCenter().postNotificationName(DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil, userInfo: userInfo);
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