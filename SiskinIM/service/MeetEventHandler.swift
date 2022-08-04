//
// MeetEventHandler.swift
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
import Martin
import UIKit

final class MeetEventHandler: XmppServiceExtension, @unchecked Sendable {
    
    static let instance = MeetEventHandler();
    
    private let queue = DispatchQueue(label: "MeetEventHandler");
    
    @Published
    private(set) var supportedAccounts: [BareJID] = [];
    
    private init() {
        
    }
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.module(.meet).eventsPublisher.sink(receiveValue: { event in
            switch event {
            case .inivitation(let action, let sender):
                switch action {
                case .propose(let id, let meetJid, _):
                    let meet = Meet(client: client, jid: meetJid.bareJid, sid: id);
                    
                    guard let callManager = CallManager.instance else {
                        return;
                    }
                       
                    Task {
                        do {
                            try await callManager.reportIncomingCall(meet);
                        } catch {
                            try await client.module(.meet).sendMessageInitiation(action: .reject(id: id), to: sender);
                        }
                    }
                case .accept(_):
                    break;
                case .proceed(_):
                    break;
                case .retract(let id):
                    CallManager.instance?.endCall(on: client.userBareJid, sid: id);
                case .reject(let id):
                    CallManager.instance?.endCall(on: client.userBareJid, sid: id);
                }

                break;
            default:
                break;
            }
        }).store(in: &cancellables);
        client.module(.disco).$accountDiscoResult.receive(on: self.queue).sink(receiveValue: { [weak self] info in
            self?.supportedAccounts.removeAll(where: { $0 != client.userBareJid });
            if !info.features.isEmpty {
                guard let that = self else {
                    return;
                }
                Task {
                    let components = try await client.module(.meet).findMeetComponents();
                    if !components.isEmpty {
                        that.queue.async {
                            that.supportedAccounts.append(client.userBareJid);
                        }
                    }
                }
            }
        }).store(in: &cancellables);
    }
    
}
