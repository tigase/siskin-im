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
    
    private static let CHAT_MSG_APPEND = "INSERT INTO chat_history (account, jid, author_jid, timestamp, item_type, data, state) VALUES (:account, :jid, :author_jid, :timestamp, :item_type, :data, :state)";
    private static let CHAT_MSGS_COUNT = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid";
    private static let CHAT_MSGS_GET = "SELECT id, author_jid, timestamp, item_type, data, state FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp LIMIT :limit OFFSET :offset"
    
    private let dbConnection:DBConnection;
    
    private lazy var msgAppendStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_APPEND);
    private lazy var msgsCountStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT);
    private lazy var msgsGetStmt:DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_GET);
    private lazy var chatUpdateTimestamp:DBStatement! = try? self.dbConnection.prepareStatement("UPDATE chats SET timestamp = :timestamp WHERE account = :account AND jid = :jid");
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    public func appendMessage(account:BareJID, message: Message) {
        let incoming = message.from != nil && message.from?.bareJid.stringValue != account.stringValue;
        let state = incoming ? State.incoming_unread : State.outgoing;
        let jid = incoming ? message.from?.bareJid : message.to?.bareJid
        let author = incoming ? message.from?.bareJid : account;
        let timestamp = NSDate();
        let params:[String:Any?] = ["account" : account.stringValue, "jid" : jid?.stringValue, "author_jid" : author?.stringValue, "timestamp": timestamp, "item_type": ItemType.message.rawValue, "data": message.body, "state": state.rawValue]
        try! msgAppendStmt.insert(params);
        let cu_params:[String:Any?] = ["account" : account.stringValue, "jid" : jid?.stringValue, "timestamp" : timestamp ];
        try! chatUpdateTimestamp.execute(cu_params);
        NSNotificationCenter.defaultCenter().postNotification(NSNotification(name: DBChatHistoryStore.MESSAGE_NEW, object: nil, userInfo: nil));
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
        default:
            log("received unsupported event", event);
        }
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