//
// SiskinPushNotificationsModuleProvider.swift
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

class SiskinPushNotificationsModuleProvider: SiskinPushNotificationsModuleProviderProtocol {
    
    func mutedChats(for account: BareJID) -> [BareJID] {
        return DBChatStore.instance.getChats(for: account).filter({ (chat) -> Bool in
            if let c = chat as? DBChat {
                return c.options.notifications == .none;
            }
            return false;
        }).map({ (chat) -> BareJID in
            return chat.jid.bareJid;
        }).sorted { (j1, j2) -> Bool in
            return j1.stringValue.compare(j2.stringValue) == .orderedAscending;
        }
    }
    
    func groupchatFilterRules(for account: BareJID) -> [TigasePushNotificationsModule.GroupchatFilter.Rule] {
        return DBChatStore.instance.getChats(for: account).filter({ (c) -> Bool in
            if let room = c as? DBRoom {
                switch room.options.notifications {
                case .none:
                    return false;
                case .always, .mention:
                    return true;
                }
            }
            return false;
        }).sorted(by: { (r1, r2) -> Bool in
            return r1.jid.bareJid.stringValue.compare(r2.jid.bareJid.stringValue) == .orderedAscending;
        }).map({ (c) -> TigasePushNotificationsModule.GroupchatFilter.Rule in
            let room = c as! DBRoom;
            switch room.options.notifications {
            case .none:
                return .never(room: room.roomJid);
            case .always:
                return .always(room: room.roomJid);
            case .mention:
                return .mentioned(room: room.roomJid, nickname: room.nickname);
            }
        });
    }
    
}
