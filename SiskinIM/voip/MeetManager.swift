//
// MeetController.swift
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
import TigaseLogging
import CallKit

class Meet: CallBase {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "meet")
        
    private static let dispatcher = QueueDispatcher(label: "MeetDispatcher");
    
    let client: XMPPClient;

    var account: BareJID {
        return client.userBareJid;
    }
    
    let jid: BareJID
    var sid: String
    
    let uuid = UUID();
    
    var name: String {
        return jid.stringValue;
    }
    
    var remoteHandle: CXHandle {
        return CXHandle(type: .generic, value: jid.stringValue);
    }
    
    let media: [Call.Media] = [.audio,.video]
    
    var description: String {
        return "Meet[on: \(client.userBareJid), with: \(jid), sid: \(sid), id: \(uuid)]";
    }
    
    func isEqual(_ call: CallBase) -> Bool {
        guard let meet = call as? Meet else {
            return false;
        }
        return meet.account == account && meet.jid == jid && meet.sid == sid;
    }
    
    func reset() {
        leave();
    }
    
    func start(completionHandler: @escaping (Result<Void, Error>) -> Void) {
        join(completionHandler: completionHandler);
    }
    
    func accept(offerMedia: [Call.Media], completionHandler: @escaping (Result<Void, Error>) -> Void) {
        join(completionHandler: completionHandler);
    }
    
    func ringing() {
        // nothing to do for now..
    }
    
    func end() {
        reset();
    }
    
    func mute(value: Bool) {
        muted(value: value);
    }
    
    init(client: XMPPClient, jid: BareJID, sid: String) {
        self.client = client;
        self.jid = jid;
        self.sid = sid;
    }
    
    @Published
    fileprivate(set) var outgoingCall: Call?;
    @Published
    fileprivate(set) var incomingCall: Call?;
    
    @Published
    fileprivate(set) var publishers: [MeetModule.Publisher] = [];
    
    private var presenceSent = false;
    private var cancellables: Set<AnyCancellable> = [];
    
    private func join(completionHandler: ((Result<Void,Error>)->Void)?) {
        let call = Call(client: client, with: jid, sid: UUID().uuidString, direction: .outgoing, media: [.audio, .video]);
        call.ringing();

        if !PresenceStore.instance.isAvailable(for: jid, context: client) {
            let presence = Presence();
            presence.to = JID(jid);
            client.writer.write(presence);
            presenceSent = true;
        }
        
        client.module(.meet).eventsPublisher.receive(on: Meet.dispatcher.queue).filter({ $0.meetJid == self.jid }).sink(receiveValue: { [weak self] event in
            self?.handle(event: event);
        }).store(in: &cancellables);
        
        PresenceStore.instance.bestPresenceEvents.filter({ $0.jid == self.jid && ($0.presence == nil || $0.presence?.type == .unavailable) }).sink(receiveValue: { _ in
            call.reset();
        }).store(in: &cancellables);
        
        MeetController.open(meet: self);
        self.outgoingCall = call;

        call.initiateOutgoingCall(with: JID(jid), completionHandler: { result in
            switch result {
            case .success(_):
                self.logger.info("initiated outgoing call of a meet \(self.jid)")
                break;
            case .failure(let error):
                self.logger.info("initiation of outgoing call of a meet \(self.jid) failed with \(error)")
                call.reset();
                self.cancellables.removeAll();
            }
            completionHandler?(result);
        })
    }
    
    public func allow(jids: [BareJID], completionHandler: @escaping (Result<[BareJID],XMPPError>)->Void) {
        client.module(.meet).allow(jids: jids, in: JID(jid), completionHandler: { result in
            completionHandler(result.map({ _ in jids }));
        });
    }
    
    public func deny(jids: [BareJID], completionHandler: @escaping (Result<[BareJID],XMPPError>)->Void) {
        client.module(.meet).deny(jids: jids, in: JID(jid), completionHandler: { result in
            completionHandler(result.map({ _ in jids }));
        });
    }
    
    private func leave() {
        cancellables.removeAll();

        outgoingCall?.reset();
        incomingCall?.reset();

        if presenceSent {
            let presence = Presence();
            presence.type = .unavailable;
            presence.to = JID(jid);
            client.writer.write(presence);
        }
    }
    
    public func muted(value: Bool) {
        outgoingCall?.mute(value: value);
    }
    
    public func switchCameraDevice() {
        outgoingCall?.switchCameraDevice();
    }
    
    func setIncomingCall(_ call: Call) {
        incomingCall = call;
        call.accept(offerMedia: []);
    }
    
    private func handle(event: MeetModule.MeetEvent) {
        switch event {
        case .publisherJoined(_, let publisher):
            publishers.append(publisher);
        case .publisherLeft(_, let publisher):
            publishers = publishers.filter({ $0.jid != publisher.jid })
        case .inivitation(_, _):
            break;
        }
    }
}
