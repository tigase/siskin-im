//
// MucEventHandler.swift
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
import UserNotifications

class MucEventHandler: XmppServiceEventHandler {
    
    static let ROOM_STATUS_CHANGED = Notification.Name("roomStatusChanged");
    static let ROOM_NAME_CHANGED = Notification.Name("roomNameChanged");
    static let ROOM_OCCUPANTS_CHANGED = Notification.Name("roomOccupantsChanged");
    
    static let instance = MucEventHandler();

    let events: [Event] = [ SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE, MucModule.OccupantChangedNickEvent.TYPE, MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.PresenceErrorEvent.TYPE, MucModule.InvitationReceivedEvent.TYPE, MucModule.InvitationDeclinedEvent.TYPE, PEPBookmarksModule.BookmarksChangedEvent.TYPE ];
    
    func handle(event: Event) {
        switch event {
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            guard !XmppService.instance.isFetch else {
                return;
            }
            if let mucModule: MucModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MucModule.ID) {
                mucModule.roomsManager.getRooms().forEach { (room) in
                    _ = room.rejoin();
                    NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
                }
            }
        case let e as MucModule.YouJoinedEvent:
            guard let room = e.room as? DBRoom else {
                return;
            }
            NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
            NotificationCenter.default.post(name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: room.presences[room.nickname]);
            updateRoomName(room: room);
        case let e as MucModule.RoomClosedEvent:
            guard let room = e.room as? DBRoom else {
                return;
            }
            NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
        case let e as MucModule.MessageReceivedEvent:
            guard let room = e.room as? DBRoom else {
                return;
            }
            
            if e.message.findChild(name: "subject") != nil {
                room.subject = e.message.subject;
                NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
            }

            if let xUser = XMucUserElement.extract(from: e.message) {
                if xUser.statuses.contains(104) {
                    self.updateRoomName(room: room);
                    XmppService.instance.refreshVCard(account: room.account, for: room.roomJid, onSuccess: nil, onError: nil);
                }
            }

            DBChatHistoryStore.instance.append(for: room.account, message: e.message, source: .stream);
        case let e as MucModule.AbstractOccupantEvent:
            NotificationCenter.default.post(name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: e);
        case let e as MucModule.PresenceErrorEvent:
            guard let error = MucModule.RoomError.from(presence: e.presence), e.nickname == nil || e.nickname! == e.room.nickname else {
                return;
            }
            print("received error from room:", e.room as Any, ", error:", error)
            
            let content = UNMutableNotificationContent();
            content.title = "Room \(e.room.roomJid.stringValue)";
            content.body = "Could not join room. Reason:\n\(error.reason)";
            content.sound = .default;
            if error != .banned && error != .registrationRequired {
                content.userInfo = ["account": e.sessionObject.userBareJid!.stringValue, "roomJid": e.room.roomJid.stringValue, "nickname": e.room.nickname, "id": "room-join-error"];
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
            UNUserNotificationCenter.current().add(request) { (error) in
                print("could not show notification:", error as Any);
            }

            guard let mucModule: MucModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            mucModule.leave(room: e.room);
        case let e as MucModule.InvitationReceivedEvent:
            NotificationCenter.default.post(name: XmppService.MUC_ROOM_INVITATION, object: e);
            break;
        case let e as PEPBookmarksModule.BookmarksChangedEvent:
            guard let client = XmppService.instance.getClient(for: e.sessionObject.userBareJid!), let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID), Settings.enableBookmarksSync.bool() else {
                return;
            }
            
            e.bookmarks?.items.filter { bookmark in bookmark is Bookmarks.Conference }.map { bookmark in bookmark as! Bookmarks.Conference }.filter { bookmark in
                return !mucModule.roomsManager.contains(roomJid: bookmark.jid.bareJid);
                }.forEach({ (bookmark) in
                    guard let nick = bookmark.nick, bookmark.autojoin else {
                        return;
                    }
                    _ = mucModule.join(roomName: bookmark.jid.localPart!, mucServer: bookmark.jid.domain, nickname: nick, password: bookmark.password);
                });
        default:
            break;
        }
    }
    
    open func sendPrivateMessage(room: DBRoom, recipientNickname: String, body: String) {
        let message = room.createPrivateMessage(body, recipientNickname: recipientNickname);
        DBChatHistoryStore.instance.appendItem(for: room.account, with: room.roomJid, state: .outgoing, authorNickname: room.nickname, authorJid: nil, recipientNickname: recipientNickname, participantId: nil, type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: body, encryption: .none, encryptionFingerprint: nil, appendix: nil, linkPreviewAction: .auto, completionHandler: nil);
        room.context.writer?.write(message);
    }
        
    fileprivate func updateRoomName(room: DBRoom) {
        guard let client = XmppService.instance.getClient(for: room.account), let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        discoModule.getInfo(for: room.jid, onInfoReceived: { (node, identities, features) in
            let newName = identities.first(where: { (identity) -> Bool in
                return identity.category == "conference";
            })?.name?.trimmingCharacters(in: .whitespacesAndNewlines);
            
            DBChatStore.instance.updateChatName(for: room.account, with: room.roomJid, name: (newName?.isEmpty ?? true) ? nil : newName);
        }, onError: nil);
    }
}

extension MucModule.RoomError {
    
    var reason: String {
        switch self {
        case .banned:
            return "User is banned";
        case .invalidPassword:
            return "Invalid password";
        case .maxUsersExceeded:
            return "Maximum number of users exceeded";
        case .nicknameConflict:
            return "Nickname already in use";
        case .nicknameLockedDown:
            return "Nickname is locked down";
        case .registrationRequired:
            return "Membership is required to access the room";
        case .roomLocked:
            return "Room is locked";
        }
    }
    
}
