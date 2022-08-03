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
import Martin

class SiskinPushNotificationsModuleProvider: SiskinPushNotificationsModuleProviderProtocol {
    
    func mutedChats(for context: Context) -> [BareJID] {
        return DBChatStore.instance.chats(for: context).filter({ $0.options.notifications == .none }).map({ $0.jid }).sorted { (j1, j2) -> Bool in
            return j1.stringValue.compare(j2.stringValue) == .orderedAscending;
        }
    }
    
    func groupchatFilterRules(for context: Context) -> [TigasePushNotificationsModule.GroupchatFilter.Rule] {
        return DBChatStore.instance.conversations(for: context.userBareJid).filter({ (c) -> Bool in
            switch c {
            case let channel as Channel:
                switch channel.options.notifications {
                case .none:
                    return false;
                case .always, .mention:
                    return true;
                }
            case let room as Room:
                switch room.options.notifications {
                case .none:
                    return false;
                case .always, .mention:
                    return true;
                }
            default:
                break;
            }
            return false;
        }).sorted(by: { (r1, r2) -> Bool in
            return r1.jid.stringValue.compare(r2.jid.stringValue) == .orderedAscending;
        }).map({ (c) -> TigasePushNotificationsModule.GroupchatFilter.Rule in
            switch c {
            case let channel as Channel:
                switch channel.options.notifications {
                case .none:
                    return .never(room: channel.channelJid);
                case .always:
                    return .always(room: channel.channelJid);
                case .mention:
                    return .mentioned(room: channel.channelJid, nickname: channel.nickname ?? "");
                }
            case let room as Room:
                switch room.options.notifications {
                case .none:
                    return .never(room: room.roomJid);
                case .always:
                    return .always(room: room.roomJid);
                case .mention:
                    return .mentioned(room: room.roomJid, nickname: room.nickname);
                }
            default:
                // should not happen
                return .never(room: c.account);
            }
        });
    }
    
}
