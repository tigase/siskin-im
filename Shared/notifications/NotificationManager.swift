//
// NotificationManager.swift
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

public class NotificationManager {
    
    public static let instance: NotificationManager = NotificationManager();
    
    public private(set) var provider: NotificationManagerProvider!;
    
    public func initialize(provider: NotificationManagerProvider) {
        self.provider = provider;
    }
    
    public static func unreadChatsThreadIds(completionHandler: @escaping (Set<String>)->Void) {
        unreadThreadIds(for: [.MESSAGE], completionHandler: completionHandler);
    }
    
    public static func unreadThreadIds(for categories: [NotificationCategory], completionHandler: @escaping (Set<String>)->Void) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let unreadChats = Set(notifications.filter({(notification) in
                let category = NotificationCategory.from(identifier: notification.request.content.categoryIdentifier);
                return categories.contains(category);
            }).map({ (notification) in
                return notification.request.content.threadIdentifier;
            }));
            
            completionHandler(unreadChats);
        }
    }
    
    public func notifyNewMessage(account: BareJID, sender: BareJID?, type kind: Payload.Kind, nickname: String?, body: String) {
    
        shouldShowNotification(account: account, sender: sender, body: body, completionHandler: { (result) in
            guard result else {
                return;
            }
            self.intNotifyNewMessage(account: account, sender: sender, type: kind, nickname: nickname, body: body);
        });
        
    }
    
    public func shouldShowNotification(account: BareJID, sender: BareJID?, body: String?, completionHandler: @escaping (Bool)->Void) {
        provider.shouldShowNotification(account: account, sender: sender, body: body) { (result) in
            if result {
                if let uid = self.generateMessageUID(account: account, sender: sender, body: body) {
                    UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { notifications in
                        let should = !notifications.contains(where: { (notification) -> Bool in
                            guard let nuid = notification.request.content.userInfo["uid"] as? String else {
                                return false;
                            }
                            return nuid == uid;
                        });
                        completionHandler(should);
                    });
                    return;
                }
            }
            completionHandler(result);
        }
    }
    
    private func intNotifyNewMessage(account: BareJID, sender: BareJID?, type kind: Payload.Kind, nickname: String?, body: String) {
        let id = UUID().uuidString;
        let content = UNMutableNotificationContent();
        prepareNewMessageNotification(content: content, account: account, sender: sender, type: kind, nickname: nickname, body: body) { (content) in
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { (error) in
                print("message notification error", error as Any);
            }
        }
    }
    
    public func prepareNewMessageNotification(content: UNMutableNotificationContent, account: BareJID, sender jid: BareJID?, type kind: Payload.Kind, nickname: String?, body msg: String?, completionHandler: @escaping (UNMutableNotificationContent)->Void) {
        content.sound = .default;
        content.categoryIdentifier = NotificationCategory.MESSAGE.rawValue;
        if let sender = jid, let body = msg {
            let uid = generateMessageUID(account: account, sender: sender, body: body)!;
            content.threadIdentifier = "account=\(account.stringValue)|sender=\(sender.stringValue)";
            self.provider.getChatNameAndType(for: account, with: sender, completionHandler: { (name, type) in
                os_log("%{public}@", log: OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "SiskinPush"), "Found: name: \(name ?? ""), type: \(type.rawValue)");
                switch type {
                case .chat:
                    content.title = name ?? sender.stringValue;
                    content.body = body;
                    content.userInfo = ["account": account.stringValue, "sender": sender.stringValue, "uid": uid];
                case .groupchat:
                    content.title = "\(name ?? sender.stringValue)";
                    content.body = body;
                    if let nickname = nickname {
                        content.subtitle = nickname;
                    }
                    content.userInfo = ["account": account.stringValue, "sender": sender.stringValue, "uid": uid];
                default:
                    break;
                }
                self.provider.countBadge(withThreadId: content.threadIdentifier, completionHandler: { count in
                    content.badge = count as NSNumber;
                    completionHandler(content);
                });
            });
        } else {
            content.threadIdentifier = "account=\(account.stringValue)";
            content.body = "New message!";
            self.provider.countBadge(withThreadId: content.threadIdentifier, completionHandler: { count in
                content.badge = count as NSNumber;
                completionHandler(content);
            });
        }
    }
    
    func generateMessageUID(account: BareJID, sender: BareJID?, body: String?) -> String? {
        if let sender = sender, let body = body {
            return Digest.sha256.digest(toHex: "\(account)|\(sender)|\(body)".data(using: .utf8));
        }
        return nil;
    }
}

public protocol NotificationManagerProvider {
    
    func getChatNameAndType(for account: BareJID, with jid: BareJID, completionHandler: @escaping (String?, Payload.Kind)->Void);
 
    func countBadge(withThreadId: String?, completionHandler: @escaping (Int)->Void);
    
    func shouldShowNotification(account: BareJID, sender: BareJID?, body: String?, completionHandler: @escaping (Bool)->Void);
    
}

public class Payload: Decodable {
    public var unread: Int;
    public var sender: JID;
    public var type: Kind;
    public var nickname: String?;
    public var message: String?;
    public var sid: String?;
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        unread = try container.decode(Int.self, forKey: .unread);
        sender = try container.decode(JID.self, forKey: .sender);
        type = Kind(rawValue: (try container.decodeIfPresent(String.self, forKey: .type)) ?? Kind.unknown.rawValue)!;
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname);
        message = try container.decodeIfPresent(String.self, forKey: .message);
        sid = try container.decodeIfPresent(String.self, forKey: .sid)
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
    }
}
