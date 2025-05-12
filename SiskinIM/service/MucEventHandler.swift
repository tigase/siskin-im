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
import Martin
import UserNotifications
import Combine
import os

final class MucEventHandler: XmppServiceExtension, Sendable {
        
    static let instance = MucEventHandler();

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MucEventHandler");
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.$state.filter({ @Sendable in
            if case .connected(let resumed) = $0 {
                return !resumed
            } else {
                return false;
            }
        }).sink(receiveValue: { @Sendable [weak client] state in
            guard let client = client else {
                return;
            }
            client.module(.muc).roomManager.rooms(for: client).forEach { (room) in
                Task {
                    DBChatMarkersStore.instance.awaitingSync(for: room as! Room);
                    do {
                        let info = try await client.module(.disco).info(for: JID(room.jid));
                        let mamVersions = info.features.compactMap(MessageArchiveManagementModule.Version.init(rawValue:));
                        await (room as! Room).roomFeatures(roomFeatures: Set(info.features.compactMap(Room.Feature.init(rawValue:))));
                        let config = RoomConfig(form: info.form);
                        if let allowPM = config.allowPM {
                            (room as! Room).allowedPM = allowPM;
                        } else {
                            (room as! Room).allowedPM = .none;
                        }
                        if let timestamp = (room as? Room)?.timestamp {
                            if !mamVersions.isEmpty {
                                let result = try await room.rejoin(fetchHistory: .skip);
                                self.logger.info("\(client.userBareJid) joined room \(room.jid) with result \(result), MAM versions: \(mamVersions) since: \(timestamp)")
                                switch result {
                                case .created(let room), .joined(let room):
                                    guard let client = room.context as? XMPPClient else {
                                        return;
                                    }
                                    Task {
                                        try await MessageEventHandler.syncMessages(for: client, version: mamVersions.contains(.MAM2) ? .MAM2 : .MAM1, componentJID: JID(room.jid), since: timestamp);
                                    }
                                }
                            } else {
                                DBChatMarkersStore.instance.syncCompleted(forAccount: room.account, with: room.jid);
                                _ = try await room.rejoin(fetchHistory: .from(timestamp))
                            }
                        } else {
                            DBChatMarkersStore.instance.syncCompleted(forAccount: room.account, with: room.jid);
                            let result = try await room.rejoin(fetchHistory: .initial);
                            self.logger.info("\(client.userBareJid) joined room \(room.jid) with result \(result), MAM versions: \(mamVersions), no sync 2")
                        }
                    } catch {
                        self.logger.error("join to room \(room.jid) failed: \(error)")
                        DBChatMarkersStore.instance.syncCompleted(forAccount: room.account, with: room.jid);
                    }
                }
            }
        }).store(in: &cancellables);
        client.module(.muc).messagesPublisher.sink(receiveValue: { @Sendable e in
            let room = e.room as! Room;
            if let subject = e.message.subject {
                // how can we find room from here?
                room.subject = subject;
            }
            if let xUser = XMucUserElement.extract(from: e.message) {
                if xUser.statuses.contains(104) {
                    Task {
                        try await self.updateRoomName(room: room);
                    }
                    Task {
                        _ = try await VCardManager.instance.refreshVCard(for: room.roomJid, on: room.account);
                    }
                }
            }
            DBChatHistoryStore.instance.append(for: room, message: e.message, source: .stream);
        }).store(in: &cancellables);
        client.module(.muc).inivitationsPublisher.sink(receiveValue: { @Sendable [weak client] invitation in
            guard let client = client, invitation.roomJid.localPart != nil else {
                return;
            }
                
            let mucModule = client.module(.muc);
            guard mucModule.roomManager.room(for: client, with: invitation.roomJid) == nil else {
                mucModule.decline(invitation: invitation, reason: nil);
                return;
            }
                
            InvitationManager.instance.addMucInvitation(for: client.userBareJid, roomJid: invitation.roomJid, invitation: invitation);
        }).store(in: &cancellables);
        client.module(.pepBookmarks).$currentBookmarks.drop(while: { @Sendable it in !Settings.enableBookmarksSync }).sink(receiveValue: { [weak client] bookmarks in
            guard let client = client else {
                return;
            }
            let mucModule = client.module(.muc);
            bookmarks.items.compactMap({ $0 as? Bookmarks.Conference }).filter({ $0.autojoin }).filter { bookmark in
                return DBChatStore.instance.conversation(for: client.userBareJid, with: bookmark.jid.bareJid) == nil;
            }.forEach({ (bookmark) in
                guard let nick = bookmark.nick else {
                        return;
                    }
                    Task {
                        _ = try await mucModule.join(roomName: bookmark.jid.localPart!, mucServer: bookmark.jid.domain, nickname: nick, password: bookmark.password);
                    }
                });
        }).store(in: &cancellables);
    }
        
    static func showJoinError(_ err: XMPPError, for room: Room) {
        guard let error = MucModule.RoomError.from(error: err), let context = room.context else {
            return;
        }
            
        let content = UNMutableNotificationContent();
        content.title = String.localizedStringWithFormat(NSLocalizedString("Room %@", comment: "alert title"), room.roomJid.description);
        content.body = String.localizedStringWithFormat(NSLocalizedString("Could not join room. Reason:\n%@", comment: "alert body"), error.reason);
        content.sound = .default;
        if error != .banned && error != .registrationRequired {
            content.userInfo = ["account": context.userBareJid.description, "roomJid": room.roomJid.description, "nickname": room.nickname, "id": "room-join-error"];
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request) { @Sendable (error) in
        }
        
        context.module(.muc).leave(room: room);
    }
            
    public func updateRoomName(room: Room) async throws {
        guard let context = room.context else { return }
        let info = try await context.module(.disco).info(for: room.jid.jid());
        let newName = info.identities.first(where: { (identity) -> Bool in
            return identity.category == "conference";
        })?.name?.trimmingCharacters(in: .whitespacesAndNewlines);
        
        room.updateRoom(name: newName);
    }
}

class CustomMucModule: MucModule, @unchecked Sendable {
    
    override func join(room: RoomProtocol, fetchHistory: RoomHistoryFetch) async throws -> RoomJoinResult {
        let result = try await super.join(room: room, fetchHistory: fetchHistory);
        Task {
            try await MucEventHandler.instance.updateRoomName(room: room as! Room);
        }
        return result;
    }
    
}

extension MucModule.RoomError {
    
    var reason: String {
        switch self {
        case .banned:
            return NSLocalizedString("User is banned", comment: "muc error reason");
        case .invalidPassword:
            return NSLocalizedString("Invalid password", comment: "muc error reason");
        case .maxUsersExceeded:
            return NSLocalizedString("Maximum number of users exceeded", comment: "muc error reason");
        case .nicknameConflict:
            return NSLocalizedString("Nickname already in use", comment: "muc error reason");
        case .nicknameLockedDown:
            return NSLocalizedString("Nickname is locked down", comment: "muc error reason");
        case .registrationRequired:
            return NSLocalizedString("Membership is required to access the room", comment: "muc error reason");
        case .roomLocked:
            return NSLocalizedString("Room is locked", comment: "muc error reason");
        }
    }
    
}
