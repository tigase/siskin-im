//
// PresenceRosterEventHandler.swift
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

class PresenceRosterEventHandler: XmppServiceEventHandler {
    
    let events: [Event] = [RosterModule.ItemUpdatedEvent.TYPE,PresenceModule.BeforePresenceSendEvent.TYPE, PresenceModule.SubscribeRequestEvent.TYPE];
        
    func handle(event: Event) {
        switch event {
        case let e as RosterModule.ItemUpdatedEvent:
            NotificationCenter.default.post(name: DBRosterStore.ITEM_UPDATED, object: e);
        case let e as PresenceModule.BeforePresenceSendEvent:
            if XmppService.instance.applicationState == .active {
                e.presence.show = Presence.Show.online;
                e.presence.priority = 5;
            } else {
                e.presence.show = Presence.Show.away;
                e.presence.priority = 0;
            }
            if let manualShow = Settings.StatusType.getString() {
                e.presence.show = Presence.Show(rawValue: manualShow);
            }
            e.presence.status = Settings.StatusMessage.getString();
        case let e as PresenceModule.SubscribeRequestEvent:
            guard let from = e.presence.from else {
                return;
            }
            var info: [String: AnyObject] = [:];
            info["account"] = e.sessionObject.userBareJid!;
            info["sender"] = from.bareJid;
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: XmppService.PRESENCE_AUTHORIZATION_REQUEST, object: self, userInfo: info);
            }
        default:
            break;
        }
    }
    
}
