//
// MainNotificationManagerProvider.swift
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

import UIKit
import Martin
import Shared
import Intents

class MainNotificationManagerProvider: NotificationManagerProvider {
    
    func avatar(on account: BareJID, for sender: BareJID) -> INImage? {
        guard let data = AvatarManager.instance.avatar(for: sender, on: account)?.jpegData(compressionQuality: 0.7) else {
            return nil;
        }
        return INImage(imageData: data);
    }
    
    func conversationNotificationDetails(for account: BareJID, with jid: BareJID, completionHandler: @escaping (ConversationNotificationDetails)->Void) {
        if let item = DBChatStore.instance.conversation(for: account, with: jid) {
            switch item {
            case let room as Room:
                completionHandler(ConversationNotificationDetails(name: room.displayName, notifications: item.notifications, type: .room, nick: room.nickname));
                return;
            case let channel as Channel:
                completionHandler(ConversationNotificationDetails(name: channel.displayName, notifications: channel.notifications, type: .channel, nick: channel.nickname));
                return;
            case let chat as Chat:
                completionHandler(ConversationNotificationDetails(name: chat.displayName, notifications: chat.notifications, type: .chat, nick: nil));
                return;
            default:
                break;
            }
        }
        completionHandler(ConversationNotificationDetails(name: DBRosterStore.instance.item(for: account, jid: JID(jid))?.name ?? jid.stringValue, notifications: .always, type: .chat, nick: nil));
    }
    
    func countBadge(withThreadId: String?, completionHandler: @escaping (Int) -> Void) {
        NotificationsManagerHelper.unreadChatsThreadIds() { result in
            var unreadChats = result;
        
            DBChatStore.instance.conversations.filter({ chat -> Bool in
                return chat.unread > 0;
            }).forEach { (chat) in
                unreadChats.insert("account=" + chat.account.stringValue + "|sender=" + chat.jid.stringValue)
            }
        
            if let threadId = withThreadId {
                unreadChats.insert(threadId);
            }
            
            completionHandler(unreadChats.count);
        }
    }
    
    func shouldShowNotification(account: BareJID, sender jid: BareJID?, body msg: String?, completionHandler: @escaping (Bool)->Void) {
        guard let sender = jid, let body = msg else {
            completionHandler(true);
            return;
        }
        
        if let conv = DBChatStore.instance.conversation(for: account, with: sender) {
            switch conv {
            case let room as Room:
                switch room.options.notifications {
                case .none:
                    completionHandler(false);
                case .always:
                    completionHandler(true);
                case .mention:
                    completionHandler(body.contains(room.nickname));
                }
            case let chat as Chat:
                switch chat.options.notifications {
                case .none:
                    completionHandler(false);
                default:
                    if Settings.notificationsFromUnknown {
                        completionHandler(true);
                    } else {
                        let known = DBRosterStore.instance.item(for: account, jid: JID(sender)) != nil;
                    
                        completionHandler(known)
                    }
                }
            case let channel as Channel:
                switch channel.options.notifications {
                case .none:
                    completionHandler(false);
                case .always:
                    completionHandler(true);
                case .mention:
                    if let nickname = channel.nickname {
                        completionHandler(body.contains(nickname));
                    } else {
                        completionHandler(false);
                    }
                }
            default:
                completionHandler(true);
            }
        } else {
            completionHandler(false);
        }
    }
    
}
