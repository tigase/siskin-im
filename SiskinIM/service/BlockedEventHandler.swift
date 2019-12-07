//
//  BlockedEventHandler.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 24/11/2019.
//  Copyright © 2019 Tigase, Inc. All rights reserved.
//

import Foundation
import TigaseSwift

class BlockedEventHandler: XmppServiceEventHandler {
    
    static let instance = BlockedEventHandler();

    let events: [Event] = [BlockingCommandModule.BlockedChangedEvent.TYPE];
    
    static func isBlocked(_ jid: JID, on client: XMPPClient) -> Bool {
        guard let blockingModule: BlockingCommandModule = client.modulesManager.getModule(BlockingCommandModule.ID) else {
            return false;
        }
        return blockingModule.blockedJids?.contains(jid) ?? false;
    }
    
    static func isBlocked(_ jid: JID, on account: BareJID) -> Bool {
        guard let client = XmppService.instance.getClient(for: account) else {
            return false;
        }
        return isBlocked(jid, on: client);
    }
    
    func handle(event: Event) {
        switch event {
        case let e as BlockingCommandModule.BlockedChangedEvent:
            (e.added + e.removed).forEach { jid in
                var p = PresenceModule.getPresenceStore(e.sessionObject).getBestPresence(for: jid.bareJid);
                if p == nil {
                    p = Presence();
                    p?.type = .unavailable;
                    p?.from = jid;
                }
                let cpc = PresenceModule.ContactPresenceChanged(sessionObject: e.sessionObject, presence: p!, availabilityChanged: true);
                NotificationCenter.default.post(name: XmppService.CONTACT_PRESENCE_CHANGED, object: cpc);
            }
        default:
            break;
        }
    }

}
