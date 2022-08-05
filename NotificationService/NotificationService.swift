//
// NotificationService.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

import BackgroundTasks
import UserNotifications
import UIKit
import Shared
import Martin
import os.log
import TigaseSQLite3
import Intents
import CryptoKit

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)? {
        didSet {
            debug("content handler set!");
        }
    }
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        debug("Received push!");
        if let bestAttemptContent = bestAttemptContent {
            bestAttemptContent.sound = UNNotificationSound.default;
            bestAttemptContent.categoryIdentifier = "MESSAGE";

            if let account = BareJID(bestAttemptContent.userInfo["account"] as? String) {
                DispatchQueue.main.async {
                    let provider = ExtensionNotificationManagerProvider();
                    self.debug("push for account:", account);
                    if let encryped = bestAttemptContent.userInfo["encrypted"] as? String, let ivStr = bestAttemptContent.userInfo["iv"] as? String {
                        if let key = NotificationEncryptionKeys.key(for: account), let data = Data(base64Encoded: encryped), let iv = Data(base64Encoded: ivStr) {
                            self.debug("got encrypted push with known key");
                            if let decoded = try? AES.GCM.open(.init(nonce: .init(data: iv), ciphertext: data, tag: Data()), using: SymmetricKey(data: key)) {
                                self.debug("got decrypted data:", String(data: decoded, encoding: .utf8) as Any);
                                if let payload = try? JSONDecoder().decode(Payload.self, from: decoded) {
                                    self.debug("decoded payload successfully!");
                                    Task {
                                        let content = await NotificationsManagerHelper.prepareNewMessageNotification(content: bestAttemptContent, account: account, sender: payload.sender.bareJid, nickname: payload.nickname, body: payload.message, provider: provider);
                                        await MainActor.run(body: {
                                            contentHandler(content);
                                        })
                                    }
                                    return;
                                }
                            }
                        }
                        contentHandler(bestAttemptContent)
                    } else {
                        self.debug("got plain push with", bestAttemptContent.userInfo[AnyHashable("sender")] as? String as Any, bestAttemptContent.userInfo[AnyHashable("body")] as? String as Any, bestAttemptContent.userInfo[AnyHashable("unread-messages")] as? Int as Any, bestAttemptContent.userInfo[AnyHashable("nickname")] as? String as Any);
                        Task {
                            let content = await NotificationsManagerHelper.prepareNewMessageNotification(content: bestAttemptContent, account: account, sender: JID(bestAttemptContent.userInfo[AnyHashable("sender")] as? String)?.bareJid, nickname: bestAttemptContent.userInfo[AnyHashable("nickname")] as? String, body: bestAttemptContent.userInfo[AnyHashable("body")] as? String, provider: provider);
                            await MainActor.run(body: {
                                contentHandler(content);
                            })
                        }
                    }
                }
                return;
            } else {
                contentHandler(bestAttemptContent);
            }
        } else {
            contentHandler(request.content);
        }
//        if #available(iOS 13.0, *) {
//            let taskRequest = BGAppRefreshTaskRequest(identifier: "org.tigase.messenger.mobile.refresh");
//            taskRequest.earliestBeginDate = nil
//            do {
//                debug("scheduling background app refresh")
//                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "org.tigase.messenger.mobile.refresh")
//                try BGTaskScheduler.shared.submit(taskRequest);
//            } catch {
//                debug("Could not schedule app refresh: \(error)")
//            }
//        }
    }
    
//    func updateNotification(content: UNMutableNotificationContent, account: BareJID, unread: Int, sender: JID, type kind: Payload.Kind, nickname: String?, body: String) {
//        let tmp = try! DBConnection.main.prepareStatement(NotificationService.GET_NAME_QUERY).findFirst(["account": account, "jid": sender.bareJid] as [String: Any?], map: { (cursor) -> (String?, Int)? in
//            return (cursor["name"], cursor["type"]!);
//        });
//        let name = tmp?.0;
//        let type: Payload.Kind = tmp?.1 == 1 ? .groupchat : .chat;
//        switch type {
//        case .chat:
//            content.title = name ?? sender.stringValue;
//            content.body = body;
//            content.userInfo = ["account": account.stringValue, "sender": sender.bareJid.stringValue];
//        case .groupchat:
//            if let nickname = nickname {
//                content.title = "\(nickname) mentioned you in \(name ?? sender.bareJid.stringValue)";
//            } else {
//                content.title = "\(name ?? sender.bareJid.stringValue)";
//            }
//            content.body = body;
//            content.userInfo = ["account": account.stringValue, "sender": sender.bareJid.stringValue];
//        default:
//            break;
//        }
//        content.categoryIdentifier = NotificationCategory.MESSAGE.rawValue;
//        //content.badge = 2;
//
//    }
    
    func debug(_ data: Any...) {
        os_log("%{public}@", log: OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "SiskinPush"), "\(Date()): \(data)");
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}

extension Query {
    
    static let buddyName = Query("select name from roster_items where account = :account and jid = :jid");
    static let conversationNotificationDetails = Query("SELECT c.type as type, c.options as options FROM chats c WHERE c.account = :account AND c.jid = :jid")
    static let listUnreadThreads = Query("select c.account, c.jid from chats c inner join chat_history ch where ch.account = c.account and ch.jid = c.jid and ch.state in (2,6,7) group by c.account, c.jid");
    static let findAvatar = Query("select ac.hash FROM avatars_cache ac WHERE ac.account = :account AND ac.jid = :jid ORDER BY ac.type ASC");
    
}

class ExtensionNotificationManagerProvider: NotificationManagerProvider {
    
    private let avatarStore = AvatarStore();
    
    func avatar(on account: BareJID, for sender: BareJID) -> INImage? {
        guard let hash = avatarStore.avatarHash(for: sender, on: account).sorted().first else {
            return nil;
        }
        
        return avatarStore.avatar(for: hash.hash)?.inImage();
    }
    
    func conversationNotificationDetails(for account: BareJID, with jid: BareJID) -> ConversationNotificationDetails {
        let options = try! Database.main.reader({ database in
            return try database.select(query: .conversationNotificationDetails, cached: false, params: ["account": account, "jid": jid]).mapFirst({ cursor -> ConversationOptionsProtocol in
                let type = ConversationType(rawValue: cursor.int(for: "type")!) ?? .chat;
                switch type {
                case .chat:
                    let options: ChatOptions = cursor.object(for: "options") ?? ChatOptions();
                    return options;
                case .room:
                    let options: RoomOptions
                    = cursor.object(for: "options") ?? RoomOptions();
                    return options;
                case .channel:
                    let options: ChannelOptions = cursor.object(for: "options")!;
                    return options;
                }
            })
        }) ?? ChatOptions();
        
        switch options {
        case let options as ChatOptions:
            let name = try! Database.main.reader({ database in
                return try database.select(query: .buddyName, cached: false, params: ["account": account, "jid": jid]).mapFirst({ $0.string(for: "name") });
            }) ?? jid.description;
            return ConversationNotificationDetails(name: name, notifications: options.notifications, type: .chat, nick: nil);
        case let options as RoomOptions:
            return ConversationNotificationDetails(name: options.name ?? jid.description, notifications: options.notifications, type: .room, nick: options.nickname);
        case let options as ChannelOptions:
            return ConversationNotificationDetails(name: options.name ?? jid.description, notifications: options.notifications, type: .channel, nick: options.nick);
        default:
            fatalError("Unsupported conversation type");
        }
    }
    
    func countBadge(withThreadId: String?) async -> Int {
        var unreadChats = await NotificationsManagerHelper.unreadChatsThreadIds();
        try? Database.main.reader({ database in
            return try database.select(query: .listUnreadThreads, cached: false, params: []).mapAll({ cursor in
                if let account = cursor.bareJid(for: "account"), let jid = cursor.bareJid(for: "jid") {
                    return "account=\(account.description)|sender=\(jid.description)"
                }
                return nil;
            })
        }).forEach({ unreadChats.insert($0) });
        

        if let threadId = withThreadId {
            unreadChats.insert(threadId);
        }
        
        return unreadChats.count;
    }
    
    func shouldShowNotification(account: BareJID, sender: BareJID?, body: String?) -> Bool {
        return true;
    }
}

class Provider {
    

    
}
//
//public struct ConversationOptions: Codable {
//
//    var name: String?;
//    var nick: String?;
//    var notifications: ConversationNotification?;
//
//    init(name: String? = nil, nick: String? = nil, notifications: ConversationNotification? = nil) {
//        self.name = name;
//        self.nick = nick;
//        self.notifications = notifications;
//    }
//
//    public init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self);
//        name = try container.decodeIfPresent(String.self, forKey: .name);
//        nick = try container.decode(String.self, forKey: .nick);
//        if let notificationsString = try container.decodeIfPresent(String.self, forKey: .notifications) {
//            notifications = ConversationNotification(rawValue: notificationsString);
//        } else {
//            notifications = nil;
//        }
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self);
//        try container.encodeIfPresent(name, forKey: .name);
//        try container.encodeIfPresent(nick, forKey: .nick);
//        try container.encodeIfPresent(notifications?.rawValue, forKey: .notifications);
//    }
//
//    enum CodingKeys: String, CodingKey {
//        case name = "name";
//        case notifications = "notifications";
//        case nick = "nick";
//    }
//
//}


