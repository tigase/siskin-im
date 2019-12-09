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

import Foundation
import TigaseSwift
import Shared

class MainNotificationManagerProvider: NotificationManagerProvider {
    
    func getChatNameAndType(for account: BareJID, with jid: BareJID, completionHandler: @escaping (String?, Payload.Kind) -> Void) {
        if let room = DBChatStore.instance.getChat(for: account, with: jid) as? DBRoom {
            completionHandler(room.name, .groupchat);
        } else {
            let client = XmppService.instance.getClient(for: account);
            let rosterModule: RosterModule? = client?.modulesManager.getModule(RosterModule.ID);
            let item = rosterModule?.rosterStore.get(for: JID(jid))
            completionHandler(item?.name, .chat);
        }
    }
    
    func countBadge(withThreadId: String?, completionHandler: @escaping (Int) -> Void) {
        NotificationManager.unreadChatsThreadIds() { result in
            var unreadChats = result;
        
            DBChatStore.instance.getChats().filter({ chat -> Bool in
                return chat.unread > 0;
            }).forEach { (chat) in
                unreadChats.insert("account=" + chat.account.stringValue + "|sender=" + chat.jid.bareJid.stringValue)
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
        
        if let conv = DBChatStore.instance.getChat(for: account, with: sender) {
            switch conv {
            case let room as DBRoom:
                switch room.options.notifications {
                case .none:
                    completionHandler(false);
                case .always:
                    completionHandler(true);
                case .mention:
                    completionHandler(body.contains(room.nickname));
                }
            case let chat as DBChat:
                switch chat.options.notifications {
                case .none:
                    completionHandler(false);
                default:
                    if Settings.NotificationsFromUnknown.bool() {
                        completionHandler(true);
                    } else {
                        let rosterModule: RosterModule? = XmppService.instance.getClient(for: account)?.modulesManager.getModule(RosterModule.ID);
                        let known = rosterModule?.rosterStore.get(for: JID(sender)) != nil;
                    
                        completionHandler(known)
                    }
                }
            default:
                print("should not happen!");
                completionHandler(true);
            }
        } else {
            completionHandler(false);
        }
    }
    
}
