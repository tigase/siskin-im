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
    
    func conversationNotificationDetails(for account: BareJID, with jid: BareJID) -> ConversationNotificationDetails {
        if let item = DBChatStore.instance.conversation(for: account, with: jid) {
            switch item {
            case let room as Room:
                return ConversationNotificationDetails(name: room.displayName, notifications: item.notifications, type: .room, nick: room.nickname);
            case let channel as Channel:
                return ConversationNotificationDetails(name: channel.displayName, notifications: channel.notifications, type: .channel, nick: channel.nickname);
            case let chat as Chat:
                return ConversationNotificationDetails(name: chat.displayName, notifications: chat.notifications, type: .chat, nick: nil);
            default:
                break;
            }
        }
        return ConversationNotificationDetails(name: DBRosterStore.instance.item(for: account, jid: JID(jid))?.name ?? jid.description, notifications: .always, type: .chat, nick: nil);
    }
    
    func countBadge(withThreadId: String?) async -> Int {
        var unreadChats = await NotificationsManagerHelper.unreadChatsThreadIds();
        DBChatStore.instance.conversations.filter({ chat -> Bool in
            return chat.unread > 0;
        }).forEach { (chat) in
            unreadChats.insert("account=" + chat.account.description + "|sender=" + chat.jid.description)
        }
    
        if let threadId = withThreadId {
            unreadChats.insert(threadId);
        }
        
        return unreadChats.count;
    }
    
    func shouldShowNotification(account: BareJID, sender jid: BareJID?, body msg: String?) -> Bool {
        guard let sender = jid, let body = msg else {
            return true;
        }
        
        if let conv = DBChatStore.instance.conversation(for: account, with: sender) {
            switch conv {
            case let room as Room:
                switch room.options.notifications {
                case .none:
                    return false;
                case .always:
                    return true;
                case .mention:
                    return body.contains(room.nickname);
                }
            case let chat as Chat:
                switch chat.options.notifications {
                case .none:
                    return false;
                default:
                    if Settings.notificationsFromUnknown {
                        return true;
                    } else {
                        return DBRosterStore.instance.item(for: account, jid: JID(sender)) != nil;
                    }
                }
            case let channel as Channel:
                switch channel.options.notifications {
                case .none:
                    return false;
                case .always:
                    return true;
                case .mention:
                    if let nickname = channel.nickname {
                        return body.contains(nickname);
                    } else {
                        return false;
                    }
                }
            default:
                return true;
            }
        } else {
            return false;
        }
    }
    
}
