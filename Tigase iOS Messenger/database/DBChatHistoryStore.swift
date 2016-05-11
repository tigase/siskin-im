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
    
    private static let CHAT_MSG_APPEND = "INSERT INTO chat_history (account, jid, author_jid, timestamp, item_type, data, state) VALUES (:account, :jid, :author_jid, :timestamp, :item_type, :data, :state)";
    private static let CHAT_MSGS_COUNT = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid";
    private static let CHAT_MSGS_COUNT_UNREAD_CHATS = "select count(1) FROM (SELECT account, jid FROM chat_history WHERE state = \(State.incoming_unread.rawValue) GROUP BY account, jid) as x";
    private static let CHAT_MSGS_GET = "SELECT id, author_jid, timestamp, item_type, data, state FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp LIMIT :limit OFFSET :offset"
    private static let CHAT_MSGS_MARK_AS_READ = "UPDATE chat_history SET state = \(State.incoming.rawValue) WHERE account = :account AND jid = :jid AND state = \(State.incoming_unread.rawValue)";
    
    private let dbConnection:DBConnection;
    
    private lazy var msgAppendStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_APPEND);
    private lazy var msgsCountStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT);
    private lazy var msgsCountUnreadChatsStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT_UNREAD_CHATS);
    private lazy var msgsGetStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_GET);
    private lazy var msgsMarkAsReadStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_MARK_AS_READ);
    private lazy var chatUpdateTimestamp:DBStatement! = try? self.dbConnection.prepareStatement("UPDATE chats SET timestamp = :timestamp WHERE account = :account AND jid = :jid");
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    public func appendMessage(account:BareJID, message: Message, carbonAction: MessageCarbonsModule.Action? = nil) {
        let body = message.body;
        // for now we support only messages with body
        guard body != nil else {
            return;
        }
        
        let incoming = message.from != nil && message.from?.bareJid.stringValue != account.stringValue;
        let state = incoming ? State.incoming_unread : State.outgoing;
        let jid = incoming ? message.from?.bareJid : message.to?.bareJid
        let author = incoming ? message.from?.bareJid : account;
        let timestamp = message.delay?.stamp ?? NSDate();
        let params:[String:Any?] = ["account" : account.stringValue, "jid" : jid?.stringValue, "author_jid" : author?.stringValue, "timestamp": timestamp, "item_type": ItemType.message.rawValue, "data": body, "state": state.rawValue]
        try! msgAppendStmt.insert(params);
        let cu_params:[String:Any?] = ["account" : account.stringValue, "jid" : jid?.stringValue, "timestamp" : timestamp ];
        try! chatUpdateTimestamp.execute(cu_params);
        
        var userInfo:[NSObject:AnyObject] = ["account": account, "sender": jid!, "incoming": incoming] ;
        if carbonAction != nil {
            userInfo["carbonAction"] = carbonAction!.rawValue;
        }
        NSNotificationCenter.defaultCenter().postNotification(NSNotification(name: DBChatHistoryStore.MESSAGE_NEW, object: nil, userInfo: userInfo));
    }
    
    public func countMessages(account:BareJID, jid:BareJID) -> Int {
        let params:[String:Any?] = ["account":account.stringValue, "jid":jid.stringValue];
        return try! msgsCountStmt.scalar(params) ?? 0;
    }
    
    public func forEachMessage(account:BareJID, jid:BareJID, limit:Int, offset: Int, forEach: (cursor:DBCursor)->Void) {
        let params:[String:Any?] = ["account":account.stringValue, "jid":jid.stringValue, "limit": limit, "offset": offset];
        try! msgsGetStmt.query(params, forEachRow: forEach);
    }
    
    public func handleEvent(event:Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            appendMessage(e.sessionObject.userBareJid!, message: e.message);
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            appendMessage(e.sessionObject.userBareJid!, message: e.message, carbonAction: e.action);
        default:
            log("received unsupported event", event);
        }
    }
    
    public func countUnreadChats() -> Int {
        return try! msgsCountUnreadChatsStmt.scalar() ?? 0;
    }
    
    public func markAsRead(account: BareJID, jid: BareJID) {
        let params:[String:Any?] = ["account":account.stringValue, "jid":jid.stringValue];
        let updatedRecords = try! msgsMarkAsReadStmt.update(params);
        if updatedRecords > 0 {
            chatItemsChanged(account, jid: jid);
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