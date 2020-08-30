//
// AvatarEventHandler.swift
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

class AvatarEventHandler: XmppServiceEventHandler {
    
    let events: [Event] = [PresenceModule.ContactPresenceChanged.TYPE, PEPUserAvatarModule.AvatarChangedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as PresenceModule.ContactPresenceChanged:
            NotificationCenter.default.post(name: XmppService.CONTACT_PRESENCE_CHANGED, object: e);
            guard let photoId = e.presence.vcardTempPhoto, let from = e.presence.from?.bareJid, let to = e.presence.to?.bareJid else {
                return;
            }
            if e.presence.findChild(name: "x", xmlns: "http://jabber.org/protocol/muc#user") == nil {
                AvatarManager.instance.avatarHashChanged(for: from, on: to, type: .vcardTemp, hash: photoId);
            } else {
                if !AvatarManager.instance.hasAvatar(withHash: photoId) {
                    XmppService.instance.retrieveVCard(account: to, for: e.presence.from, completionHandler: { result in
                        switch result {
                        case .success(let vcard):
                            if let photo = vcard.photos.first {
                                AvatarManager.fetchData(photo: photo, completionHandler: { result in
                                    if let data = result {
                                        _ = AvatarManager.instance.storeAvatar(data: data);
                                    }
                                })
                            }
                        case .failure(let error):
                            print("could not retrieve a vcard from:", e.presence.from as Any, "on:", to, "error:", error);
                        }
                    })
                }
            }
        case let e as PEPUserAvatarModule.AvatarChangedEvent:
            guard let item = e.info.first(where: { info -> Bool in
                return info.url == nil;
            }) else {
                return;
            }
            AvatarManager.instance.avatarHashChanged(for: e.jid.bareJid, on: e.sessionObject.userBareJid!, type: .pepUserAvatar, hash: item.id);
        default:
            break;
        }
    }
    
    
}
