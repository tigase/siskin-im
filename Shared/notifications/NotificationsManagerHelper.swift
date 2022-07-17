//
// NotificationsManagerHelper.swift
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

import Foundation
import TigaseSwift
import UserNotifications
import os
import Intents
import UIKit
import CryptoKit

public struct ConversationNotificationDetails {
    public let name: String;
    public let notifications: ConversationNotification;
    public let type: ConversationType;
    public let nick: String?;
    
    public init(name: String, notifications: ConversationNotification, type: ConversationType, nick: String?) {
        self.name = name;
        self.notifications = notifications;
        self.type = type;
        self.nick = nick;
    }
}

public class NotificationsManagerHelper {
    
    public static func unreadChatsThreadIds() async -> Set<String> {
        return await unreadThreadIds(for: [.MESSAGE]);
    }
    
    public static func unreadThreadIds(for categories: [NotificationCategory]) async -> Set<String> {
        return await withUnsafeContinuation({ continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
                let unreadChats = Set(notifications.filter({(notification) in
                    let category = NotificationCategory.from(identifier: notification.request.content.categoryIdentifier);
                    return categories.contains(category);
                }).map({ (notification) in
                    return notification.request.content.threadIdentifier;
                }));
                
                continuation.resume(returning: unreadChats);
            }
        })
    }
    
    public static func generateMessageUID(account: BareJID, sender: BareJID?, body: String?) -> String? {
        if let sender = sender, let body = body {
            return SHA256.hash(toHex: "\(account)|\(sender)|\(body)", using: .utf8);
        }
        return nil;
    }
        
    public static func prepareNewMessageNotification(content: UNMutableNotificationContent, account: BareJID, sender jid: BareJID?, nickname: String?, body msg: String?, provider: NotificationManagerProvider) async -> UNNotificationContent {
        let timestamp = Date();
        content.sound = .default;        
        content.categoryIdentifier = NotificationCategory.MESSAGE.rawValue;
        
        if let sender = jid, let body = msg {
            let uid = generateMessageUID(account: account, sender: sender, body: body)!;
            content.threadIdentifier = "account=\(account.description)|sender=\(sender.description)";
            let details = provider.conversationNotificationDetails(for: account, with: sender);
            os_log("%{public}@", log: OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "SiskinPush"), "Found: name: \(details.name), type: \(String(describing: details.type.rawValue))");
            
            var senderId: String = sender.description;
            var group: INSpeakableString?;
            switch details.type {
            case .chat:
                content.title = details.name;
                if body.starts(with: "/me ") {
                    content.body = String(body.dropFirst(4));
                } else {
                    content.body = body;
                }
            case .channel, .room:
                content.title = details.name
                group = INSpeakableString(spokenPhrase: details.name);
                if body.starts(with: "/me ") {
                    if let nickname = nickname {
                        content.body = "\(nickname) \(body.dropFirst(4))";
                    } else {
                        content.body = String(body.dropFirst(4));
                    }
                } else {
                    content.body = body;
                    if let nickname = nickname {
                        content.subtitle = nickname;
                        senderId = sender.with(resource: nickname).description;
                    }
                }
            }
            content.userInfo = ["account": account.description, "sender": sender.description, "uid": uid, "timestamp": timestamp];
            content.badge = (await provider.countBadge(withThreadId: content.threadIdentifier)) as NSNumber;
            if #available(iOS 15.0, *) {
                do {
                    let recipient = INPerson(personHandle: INPersonHandle(value: account.description, type: .unknown), nameComponents: nil, displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil, isMe: true, suggestionType: .none);
                    let avatar = provider.avatar(on: account, for: sender);
                    let sender = INPerson(personHandle: INPersonHandle(value: senderId, type: .unknown), nameComponents: nil, displayName: group == nil ? details.name : nickname, image: avatar, contactIdentifier: nil, customIdentifier: senderId, isMe: false, suggestionType: .instantMessageAddress);
                    let intent = INSendMessageIntent(recipients: group == nil ? [recipient] : [recipient, sender], outgoingMessageType: .outgoingMessageText, content: nil, speakableGroupName: group, conversationIdentifier: content.threadIdentifier, serviceName: "Siskin IM", sender: sender, attachments: nil);
                    if details.type == .chat {
                        intent.setImage(avatar, forParameterNamed: \.sender);
                    } else {
                        intent.setImage(avatar, forParameterNamed: \.speakableGroupName);
                    }
                    let interaction = INInteraction(intent: intent, response: nil);
                    interaction.direction = .incoming;
                    interaction.donate(completion: nil);
                    return try content.updating(from: intent);
                } catch {
                    // some error happened
                }
            }
            return content;
        } else {
            content.threadIdentifier = "account=\(account.description)";
            content.body = NSLocalizedString("New message!", comment: "new message without content notification");
            content.badge = (await provider.countBadge(withThreadId: content.threadIdentifier)) as NSNumber;
            
            return content;
        }
    }
}

public protocol NotificationManagerProvider {
    
    func conversationNotificationDetails(for account: BareJID, with jid: BareJID) -> ConversationNotificationDetails;
 
    func countBadge(withThreadId: String?) async -> Int;
    
    func shouldShowNotification(account: BareJID, sender: BareJID?, body: String?) -> Bool;
    
    func avatar(on account: BareJID, for sender: BareJID) -> INImage?;
    
}

public class Payload: Decodable {
    public var unread: Int;
    public var sender: JID;
    public var type: Kind;
    public var nickname: String?;
    public var message: String?;
    public var sid: String?;
    public var media: [String]?;
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        unread = try container.decode(Int.self, forKey: .unread);
        sender = try container.decode(JID.self, forKey: .sender);
        type = Kind(rawValue: (try container.decodeIfPresent(String.self, forKey: .type)) ?? Kind.unknown.rawValue)!;
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname);
        message = try container.decodeIfPresent(String.self, forKey: .message);
        sid = try container.decodeIfPresent(String.self, forKey: .sid)
        media = try container.decodeIfPresent([String].self, forKey: .media);
        // -- and so on...
    }
    
    public enum Kind: String {
        case unknown
        case groupchat
        case chat
        case call
    }
    
    public enum CodingKeys: String, CodingKey {
        case unread
        case sender
        case type
        case nickname
        case message
        case sid
        case media
    }
}
