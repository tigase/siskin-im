//
// DBChatHistoryStore.swift
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
import TigaseSwift
import TigaseSwiftOMEMO

open class DBChatHistoryStore: Logger {
    
    public static let MESSAGE_NEW = Notification.Name("messengerMessageNew");
    public static let MESSAGE_UPDATED = Notification.Name("messengerMessageUpdated");
    public static let MESSAGE_REMOVED = Notification.Name("messageRemoved");
    
    fileprivate static let CHAT_GET_ID_WITH_ACCOUNT_PARTICIPANT_AND_STANZA_ID = "SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND stanza_id = :stanzaId";
    fileprivate static let CHAT_MSG_APPEND = "INSERT INTO chat_history (account, jid, author_jid, author_nickname, timestamp, item_type, data, stanza_id, state, encryption, fingerprint) VALUES (:account, :jid, :author_jid, :author_nickname, :timestamp, :item_type, :data, :stanza_id, :state, :encryption, :fingerprint)";
    fileprivate static let CHAT_MSGS_COUNT = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_MSGS_DELETE = "DELETE FROM chat_history WHERE account = :account AND jid = :jid";
    fileprivate static let CHAT_MSGS_GET = "SELECT id, author_jid, author_nickname, timestamp, item_type, data, state, preview, encryption, fingerprint FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp DESC LIMIT :limit OFFSET :offset"
    fileprivate static let CHAT_MSG_UPDATE_PREVIEW = "UPDATE chat_history SET preview = :preview WHERE id = :id";
    fileprivate static let CHAT_MSGS_MARK_AS_READ = "UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))";
    fileprivate static let CHAT_MSGS_MARK_AS_READ_BEFORE = "UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))";
    fileprivate static let CHAT_MSG_CHANGE_STATE = "UPDATE chat_history SET state = :newState, timestamp = COALESCE(:timestamp, timestamp) WHERE id = :id AND (:oldState IS NULL OR state = :oldState)";
    fileprivate static let MSG_ALREADY_ADDED = "SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND (:data IS NULL OR data = :data) AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (state % 2 == :direction) AND (:author_nickname is null OR author_nickname = :author_nickname)";

    public let dbConnection:DBConnection;
    
    fileprivate lazy var appendMessageStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_APPEND);
    fileprivate lazy var msgsCountStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_COUNT);
    fileprivate lazy var msgsDeleteStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_DELETE);
    fileprivate lazy var msgGetIdWithAccountPariticipantAndStanzaIdStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_GET_ID_WITH_ACCOUNT_PARTICIPANT_AND_STANZA_ID);
    fileprivate lazy var msgsMarkAsReadStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_MARK_AS_READ);
    fileprivate lazy var msgsMarkAsReadBeforeStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSGS_MARK_AS_READ_BEFORE);
    fileprivate lazy var msgUpdatePreviewStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_UPDATE_PREVIEW);
    fileprivate lazy var msgUpdateStateStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.CHAT_MSG_CHANGE_STATE);
    open lazy var checkItemAlreadyAddedStmt: DBStatement! = try? self.dbConnection.prepareStatement(DBChatHistoryStore.MSG_ALREADY_ADDED);
    fileprivate lazy var listUnreadChatsStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT DISTINCT account, jid FROM chat_history WHERE state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate lazy var getMessagePositionStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND timestamp < (SELECT timestamp FROM chat_history WHERE id = :msgId)");
    fileprivate lazy var getMessagePositionStmtInverted: DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)");
    fileprivate lazy var markMessageAsErrorStmt: DBStatement! = try? self.dbConnection.prepareStatement("UPDATE chat_history SET state = :state, error = :error WHERE id = :id");
    fileprivate lazy var getMessageErrorDetails: DBStatement! = try? self.dbConnection.prepareStatement("SELECT error FROM chat_history WHERE id = ?");
    fileprivate lazy var getChatMessageWithIdStmt: DBStatement! = try! self.dbConnection.prepareStatement("SELECT id, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error FROM chat_history WHERE id = :id");
    fileprivate let getUnsentMessagesForAccountStmt: DBStatement;
    fileprivate let getChatMessagesStmt: DBStatement;
    fileprivate lazy var removeItemStmt: DBStatement! = try! self.dbConnection.prepareStatement("DELETE FROM chat_history WHERE id = :id");
    fileprivate lazy var countUnsentMessagesStmt: DBStatement! = try! self.dbConnection.prepareStatement("SELECT count(id) FROM chat_history WHERE state = \(MessageState.outgoing_unsent.rawValue)");

    
    
    fileprivate let dispatcher: QueueDispatcher;
    
    public static let instance = DBChatHistoryStore(dbConnection: DBConnection.main);
    
    public init(dbConnection:DBConnection) {
        self.dispatcher = QueueDispatcher(label: "chat_history_store");
        self.dbConnection = dbConnection;
        self.getUnsentMessagesForAccountStmt = try! self.dbConnection.prepareStatement("SELECT ch.account as account, ch.jid as jid, ch.data as data, ch.stanza_id as stanza_id, ch.encryption as encryption FROM chat_history ch WHERE ch.account = :account AND ch.state = \(MessageState.outgoing_unsent.rawValue) ORDER BY timestamp ASC");
        self.getChatMessagesStmt = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");
        super.init();
        NotificationCenter.default.addObserver(self, selector: #selector(DBChatHistoryStore.accountRemoved), name: NSNotification.Name(rawValue: "accountRemoved"), object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(DBChatHistoryStore.imageRemovedFromCache), name: ImageCache.DISK_CACHE_IMAGE_REMOVED, object: nil);
    }
            
    public func appendItem(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String? = nil, authorJid: BareJID? = nil, type: ItemType = .message, timestamp: Date, stanzaId id: String?, data: String, chatState: ChatState? = nil, errorCondition: ErrorCondition? = nil, errorMessage: String? = nil, encryption: MessageEncryption, encryptionFingerprint: String?, completionHandler: ((Int)->Void)?) {
        dispatcher.async {
            guard !state.isError || id == nil || !self.processOutgoingError(for: account, with: jid, stanzaId: id!, errorCondition: errorCondition, errorMessage: errorMessage) else {
                return;
            }
            
            guard !self.checkItemAlreadyAdded(for: account, with: jid, authorNickname: authorNickname, type: type, timestamp: timestamp, direction: state.direction, stanzaId: id, data: data) else {
                return;
            }
            
            let params:[String:Any?] = ["account" : account, "jid" : jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.rawValue, "stanza_id": id, "author_jid" : authorJid, "author_nickname": authorNickname, "encryption": encryption.rawValue, "fingerprint": encryptionFingerprint]
            guard let msgId = try! self.appendMessageStmt.insert(params) else {
                return;
            }
            completionHandler?(msgId);
            
            let item = ChatMessage(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
            DBChatStore.instance.newMessage(for: account, with: jid, timestamp: timestamp, message: encryption.message() ?? data, state: state, remoteChatState: state.direction == .incoming ? chatState : nil) {
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: item);
            }
        }
    }
    
    fileprivate func processOutgoingError(for account: BareJID, with jid: BareJID, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) -> Bool {

        guard let itemId = self.getMessageIdInt(account: account, jid: jid, stanzaId: stanzaId) else {
            return false;
        }

        let params: [String: Any?] = ["id": itemId, "state": MessageState.outgoing_error_unread.rawValue, "error": errorMessage ?? errorCondition?.rawValue ?? "Unknown error"];
        guard try! self.markMessageAsErrorStmt.update(params) > 0 else {
            return false;
        }
        
        DBChatStore.instance.newMessage(for: account, with: jid, timestamp: Date(timeIntervalSince1970: 0), message: nil, state: .outgoing_error_unread) {
            self.itemUpdated(withId: itemId, for: account, with: jid);
        }
        return true;
    }

    open func history(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int, completionHandler: @escaping (([ChatViewItemProtocol]) -> Void)) {
        dispatcher.async {
//            let count = try! self.msgsCountStmt.scalar(["account": account, "jid": jid] as [String : Any?]) ?? 0;
            if before != nil {
                let params: [String: Any?] = ["account": account, "jid": jid, "msgId": before!];
                let offset = try! self.getMessagePositionStmtInverted.scalar(params)!;
                completionHandler( self.history(for: account, jid: jid, offset: offset, limit: limit));
            } else {
                completionHandler(self.history(for: account, jid: jid, offset: 0, limit: limit));
            }
        }
    }

    open func history(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int) -> [ChatViewItemProtocol] {
        return dispatcher.sync {
            if before != nil {
                let offset = try! getMessagePositionStmtInverted.scalar(["account": account, "jid": jid, "msgId": before!])!;
                return history(for: account, jid: jid, offset: offset, limit: limit);
            } else {
                return history(for: account, jid: jid, offset: 0, limit: limit);
            }
        }
    }
    
    fileprivate func history(for account: BareJID, jid: BareJID, offset: Int, limit: Int) -> [ChatViewItemProtocol] {
        let params: [String: Any?] = ["account": account, "jid": jid, "offset": offset, "limit": limit];
        return try! getChatMessagesStmt.query(params) { (cursor) -> ChatViewItemProtocol? in
            return itemFrom(cursor: cursor, for: account, with: jid);
        }
    }
    
    open func checkItemAlreadyAdded(for account: BareJID, with jid: BareJID, authorNickname: String? = nil, type: ItemType, timestamp: Date, direction: MessageDirection, stanzaId: String?, data: String?) -> Bool {
        let range = stanzaId == nil ? 5.0 : 60.0;
        let ts_from = timestamp.addingTimeInterval(-60 * range);
        let ts_to = timestamp.addingTimeInterval(60 * range);
        
        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": type.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];
        
        return (try! checkItemAlreadyAddedStmt.scalar(params) ?? 0) > 0;
    }
                
    open func countUnsentMessages(completionHandler: @escaping (Int)->Void) {
        dispatcher.async {
            let result = try! self.countUnsentMessagesStmt.scalar() ?? 0;
            completionHandler(result);
        }
    }
    
    open func forEachUnreadChat(forEach: (_ account: BareJID, _ jid: BareJID)->Void) {
        try! listUnreadChatsStmt.query(forEach: { (cursor) -> Void in
            let account: BareJID = cursor["account"]!;
            let jid: BareJID = cursor["jid"]!;
            forEach(account, jid);
        });
    }
    
    open func markOutgoingAsError(for account: BareJID, with jid: BareJID, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) {
        dispatcher.async {
            _ = self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId, errorCondition: errorCondition, errorMessage: errorMessage);
        }
    }
    
    open func markAsRead(for account: BareJID, with jid: BareJID, before: Date? = nil) {
        dispatcher.async {
            if before == nil {
                let params:[String:Any?] = ["account":account, "jid":jid];
                let updatedRecords = try! self.msgsMarkAsReadStmt.update(params);
                if updatedRecords > 0 {
                    DBChatStore.instance.markAsRead(for: account, with: jid);
                }
            } else {
                let params:[String:Any?] = ["account":account, "jid":jid, "before": before];
                let updatedRecords = try! self.msgsMarkAsReadBeforeStmt.update(params);
                if updatedRecords > 0 {
                    DBChatStore.instance.markAsRead(for: account, with: jid, count: updatedRecords);
                }
            }
        }
    }
    
    open func removeItem(for account: BareJID, with jid: BareJID, itemId: Int) {
        dispatcher.async {
            let params: [String: Any?] = ["id": itemId];
            guard (try! self.removeItemStmt.update(params)) > 0 else {
                return;
            }
            self.itemRemoved(withId: itemId, for: account, with: jid);
        }
    }
    
    open func updateItem(for account: BareJID, with jid: BareJID, id: Int, preview: String?) {
        dispatcher.async {
            let params: [String:Any?] = ["id": id, "preview": preview];
            if try! self.msgUpdatePreviewStmt.update(params) > 0 {
                self.itemUpdated(withId: id, for: account, with: jid);
            }
        }
    }
        
    fileprivate func getMessageIdInt(account: BareJID, jid: BareJID, stanzaId: String?) -> Int? {
        guard stanzaId != nil else {
            return nil;
        }
        let idParams: [String: Any?] = ["account": account, "jid": jid, "stanzaId": stanzaId!];
        guard let msgId = try! self.msgGetIdWithAccountPariticipantAndStanzaIdStmt.scalar(idParams) else {
            return nil;
        }

        return msgId;
    }
    
    open func deleteMessages(for account: BareJID, with jid: BareJID) {
        let params:[String:Any?] = ["account":account, "jid":jid];
        _ = try! self.msgsDeleteStmt.update(params);
    }
    
    open func updateItemState(for account: BareJID, with jid: BareJID, stanzaId: String?, from oldState: MessageState, to newState: MessageState, withTimestamp timestamp: Date? = nil) {
        dispatcher.async {
            guard let itemId = self.getMessageIdInt(account: account, jid: jid, stanzaId: stanzaId) else {
                return;
            }
            self.updateItemState(for: account, with: jid, itemId: itemId, from: oldState, to: newState, withTimestamp: timestamp);
        }
    }
    
    open func updateItemState(for account: BareJID, with jid: BareJID, itemId: Int, from oldState: MessageState, to newState: MessageState, withTimestamp timestamp: Date? = nil) {
        dispatcher.async {
            let params: [String: Any?] = ["id": itemId, "oldState": oldState.rawValue, "newState": newState.rawValue, "timestamp": timestamp];
            if try! self.msgUpdateStateStmt.update(params) > 0 {
                self.itemUpdated(withId: itemId, for: account, with: jid);
            }
        }
    }
    
    open func loadUnsentMessage(for account: BareJID, completionHandler: @escaping (BareJID,BareJID,String,String,MessageEncryption)->Void) {
        dispatcher.async {
            try! self.getUnsentMessagesForAccountStmt.query(["account": account] as [String : Any?], forEach: { (cursor) in
                let jid: BareJID = cursor["jid"]!;
                let data: String = cursor["data"]!;
                let stanzaId: String = cursor["stanza_id"]!;
                let encryption: MessageEncryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
                
                completionHandler(account, jid, data, stanzaId, encryption);
            });
        }
    }
    
    fileprivate func changeMessageState(account: BareJID, jid: BareJID, stanzaId: String, oldState: MessageState, newState: MessageState, completion: ((Int)->Void)?) {
        dispatcher.async {
        }
    }
    
    fileprivate func itemUpdated(withId id: Int, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            let params: [String: Any?] = ["id": id]
            try! self.getChatMessageWithIdStmt.query(params, forEach: { (cursor) in
                guard let item = self.itemFrom(cursor: cursor, for: account, with: jid) else {
                    return;
                }
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
            });
        }
    }
 
    fileprivate func itemRemoved(withId id: Int, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_REMOVED, object: DeletedMessage(id: id, account: account, jid: jid));
        }
    }
    
    @objc open func accountRemoved(_ notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            _ = try! dbConnection.prepareStatement("DELETE FROM chat_history WHERE account = ?").update(accountStr);
        }
    }
    
    @objc open func imageRemovedFromCache(_ notification: NSNotification) {
        if let data = notification.userInfo {
            let url = data["url"] as! URL;
            _ = try! dbConnection.prepareStatement("UPDATE chat_history SET preview = null WHERE preview = ?").update("preview:image:\(url.pathComponents.last!)");
        }
    }
        
    fileprivate func itemFrom(cursor: DBCursor, for account: BareJID, with jid: BareJID) -> ChatViewItemProtocol? {
        let id: Int = cursor["id"]!;
        let stateInt: Int = cursor["state"]!;
        let timestamp: Date = cursor["timestamp"]!;
        let message: String = cursor["data"]!;
        let authorNickname: String? = cursor["author_nickname"];
        let authorJid: BareJID? = cursor["author_jid"];
        let encryption: MessageEncryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
        let encryptionFingerprint: String? = cursor["fingerprint"];
        let error: String? = cursor["error"];
        
        var preview: String? = cursor["preview"];
        return ChatMessage(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, preview: preview, error: error);
    }
}

public enum MessageState: Int {
    case incoming = 0
    case outgoing = 1
    
    case incoming_unread = 2
    case outgoing_unsent = 3

    case outgoing_error = 4 //7
    case incoming_error = 5 //9

    case incoming_error_unread = 6 //8
    case outgoing_error_unread = 7 //6

    case outgoing_delivered = 9 //4
    case outgoing_read = 11//5
    
    var direction: MessageDirection {
        switch self {
        case .incoming, .incoming_unread, .incoming_error_unread, .incoming_error:
            return .incoming;
        case .outgoing, .outgoing_unsent, .outgoing_delivered, .outgoing_read, .outgoing_error_unread, .outgoing_error:
            return .outgoing;
        }
    }
    
    var isError: Bool {
        switch self {
        case .incoming_error, .incoming_error_unread, .outgoing_error, .outgoing_error_unread:
            return true;
        default:
            return false;
        }
    }
    
    var isUnread: Bool {
        switch self {
        case .incoming_unread, .incoming_error_unread, .outgoing_error_unread:
            return true;
        default:
            return false;
        }
    }
}

public enum MessageDirection: Int {
    case incoming = 0
    case outgoing = 1
}
    
public enum ItemType:Int {
    case message = 0
}

class ChatMessage: ChatViewItemProtocol {
    
    let id: Int;
    let timestamp: Date;
    let account: BareJID;
    let message: String;
    let jid: BareJID;
    let state: MessageState;
    let authorNickname: String?;
    let authorJid: BareJID?;
    let preview: String?;
    let error: String?;
    
    let encryption: MessageEncryption;
    let encryptionFingerprint: String?;
    
    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, message: String, authorNickname: String?, authorJid: BareJID?, encryption: MessageEncryption, encryptionFingerprint: String?, preview: String? = nil, error: String?) {
        self.id = id;
        self.timestamp = timestamp;
        self.account = account;
        self.message = message;
        self.jid = jid;
        self.state = state;
        self.authorNickname = authorNickname;
        self.authorJid = authorJid;
        self.preview = preview;
        self.encryption = encryption;
        self.encryptionFingerprint = encryptionFingerprint;
        self.error = error;
    }
 
    func isMergeable(with: ChatViewItemProtocol) -> Bool {
        guard let item = with as? ChatMessage else {
            return false;
        }
        
        return self.account == item.account && self.jid == item.jid && self.state.direction == item.state.direction && self.authorNickname == item.authorNickname && self.authorJid == item.authorJid && abs(self.timestamp.timeIntervalSince(item.timestamp)) < allowedTimeDiff() && self.encryption == item.encryption && self.encryptionFingerprint == item.encryptionFingerprint;
    }
    
    func allowedTimeDiff() -> TimeInterval {
        switch /*Settings.messageGrouping.string() ??*/ "smart" {
        case "none":
            return -1.0;
        case "always":
            return 60.0 * 60.0 * 24.0;
        default:
            return 30.0;
        }
    }

}

class DeletedMessage: ChatViewItemProtocol {
    
    let id: Int;
    let account: BareJID;
    let jid: BareJID;
    
    let timestamp: Date = Date();
    let state: MessageState = .outgoing;
    let encryption: MessageEncryption = .none;
    let encryptionFingerprint: String? = nil;

    init(id: Int, account: BareJID, jid: BareJID) {
        self.id = id;
        self.account = account;
        self.jid = jid;
    }
    
    func isMergeable(with item: ChatViewItemProtocol) -> Bool {
        return false;
    }
    
}
