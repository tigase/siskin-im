//
//  BlockedEventHandler.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 24/11/2019.
//  Copyright © 2019 Tigase, Inc. All rights reserved.
//

import Foundation
import Martin

import Foundation
import Martin
import Combine

class BlockedEventHandler: XmppServiceExtension {
    
    static let instance = BlockedEventHandler();

    static func isBlocked(_ jid: JID, on client: Context) -> Bool {
        return client.module(.blockingCommand).blockedJids?.contains(jid) ?? false;
    }
    
    static func isBlocked(_ jid: JID, on account: BareJID) -> Bool {
        guard let client = XmppService.instance.getClient(for: account) else {
            return false;
        }
        return isBlocked(jid, on: client);
    }
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        var prev: [JID] = [];
        client.module(.blockingCommand).$blockedJids.map({ $0 ?? []}).sink(receiveValue: { [weak client] blockedJids in
            guard let client = client else {
                return;
            }

            let prevSet = Set(prev);
            let blockedSet = Set(blockedJids);
            
            let changes = blockedJids.filter({ !prevSet.contains($0) }) + prev.filter({ !blockedSet.contains($0) });
            
            prev = blockedJids;
            
            for jid in changes {
                var p = PresenceStore.instance.bestPresence(for: jid.bareJid, context: client);
                if p == nil {
                    p = Presence();
                    p?.type = .unavailable;
                    p?.from = jid;
                }
                ContactManager.instance.update(presence: p!, for: .init(account: client.userBareJid, jid: jid.bareJid, type: .buddy))
            }
        }).store(in: &cancellables);
    }
    
}
