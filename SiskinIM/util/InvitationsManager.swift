//
// InvitationsManager.swift
//
// Siskin IM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import Combine
import TigaseSwift
import UserNotifications

class InvitationManager {
 
    static let instance = InvitationManager();
    
    func addPresenceSubscribe(for account: BareJID, from jid: JID) {
        let senderName = DBRosterStore.instance.item(for: account, jid: jid.withoutResource())?.name ?? jid.description;
        let content = UNMutableNotificationContent();
        content.body = String.localizedStringWithFormat(NSLocalizedString("Received presence subscription request from %@", comment: "presence subscription request notification"), senderName);
        content.userInfo = ["sender": jid.description as NSString, "account": account.description as NSString, "senderName": senderName as NSString];
        content.categoryIdentifier = "SUBSCRIPTION_REQUEST";
        content.threadIdentifier = "account=\(account.description)|sender=\(jid.description)";
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }
    
    func addMucInvitation(for account: BareJID, roomJid: BareJID, invitation: MucModule.Invitation) {
        let content = UNMutableNotificationContent();
        content.body = String.localizedStringWithFormat(NSLocalizedString("Invitation to groupchat %@", comment: "muc invitation notification"), roomJid.description);
        if let from = invitation.inviter, let name = DBRosterStore.instance.item(for: account, jid: from.withoutResource())?.name {
            content.body = "\(content.body) from \(name)";
        }
        content.threadIdentifier = "mucRoomInvitation=\(account.description)|room=\(roomJid.description)";
        content.categoryIdentifier = "MUC_ROOM_INVITATION";
        content.userInfo = ["account": account.description, "roomJid": roomJid.description, "password": invitation.password as Any];
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil), withCompletionHandler: nil);
    }
    
    func rejectPresenceSubscription(for account: BareJID, from jid: JID) {
        let threadId = "account=\(account.description)|sender=\(jid.description)";
        UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { notifications in
            let subscriptionReqNotifications = notifications.filter({ $0.request.content.categoryIdentifier == "SUBSCRIPTION_REQUEST" && $0.request.content.threadIdentifier == threadId });
            guard !subscriptionReqNotifications.isEmpty else {
                return;
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: subscriptionReqNotifications.map({ $0.request.identifier }));
            XmppService.instance.getClient(for: account)?.module(.presence).unsubscribed(by: jid);
        })
    }
}
