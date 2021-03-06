//
// JingleManager_Session.swift
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
import WebRTC
import Combine

extension JingleManager {

    class Session: JingleSession {
                
        public let id = UUID().uuidString;
                        
        private var cachedRemoteCandidates: [[String]] = [];
        private var remoteCandidatesSubject = PassthroughSubject<RTCIceCandidate,Never>();
        public let remoteCandidatesPublisher: AnyPublisher<RTCIceCandidate,Never>;
        
        @Published
        private(set) var remoteDescription: SDP?;
                
        override init(context: Context, jid: JID, sid: String, role: Jingle.Content.Creator, initiationType: JingleSessionInitiationType) {
            remoteCandidatesPublisher = remoteCandidatesSubject.makeConnectable().autoconnect().eraseToAnyPublisher();
            super.init(context: context, jid: jid, sid: sid, role: role, initiationType: initiationType);
        }
        
        override func initiated(contents: [Jingle.Content], bundle: [String]?) {
            super.initiated(contents: contents, bundle: bundle)
            self.remoteDescription = SDP(contents: contents, bundle: bundle);
        }
        
        override func accept() {
            super.accept();
        }
                
        override func accepted(contents: [Jingle.Content], bundle: [String]?) {
            super.accepted(contents: contents, bundle: bundle)
            self.remoteDescription = SDP(contents: contents, bundle: bundle);
        }
        
        func decline() {
            self.terminate(reason: .decline);
        }
                
        func addCandidate(_ candidate: Jingle.Transport.ICEUDPTransport.Candidate, for contentName: String) {
            let sdp = candidate.toSDP();
            
            cachedRemoteCandidates.append([contentName, sdp]);
            receivedRemoteCandidates();
        }
        
        #if targetEnvironment(simulator)
        private func receivedRemoteCandidates() {
        }
        #else
        private func receivedRemoteCandidates() {
            guard self.remoteDescription != nil else {
                return;
            }
            
            for arr in cachedRemoteCandidates {
                let contentName = arr[0];
                let sdp = arr[1];
                guard let lines = self.remoteDescription?.toString(withSid: "0").split(separator: "\r\n").map({ (s) -> String in
                    return String(s);
                }) else {
                    return;
                }
                
                let contents = lines.filter { (line) -> Bool in
                    return line.starts(with: "a=mid:");
                };
                
                let idx = contents.firstIndex(of: "a=mid:\(contentName)") ?? lines.filter({ (line) -> Bool in
                    return line.starts(with: "m=")
                }).firstIndex(where: { (line) -> Bool in
                    return line.starts(with: "m=\(contentName) ");
                }) ?? 0;
                
                print("adding candidate for:", idx, "name:", contentName, "sdp:", sdp)
                remoteCandidatesSubject.send(RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: contentName));
            }
            cachedRemoteCandidates.removeAll();
        }
        #endif
                
        fileprivate func onError(_ errorCondition: ErrorCondition) {
            
        }
        
        func sendLocalCandidate(_ candidate: RTCIceCandidate, peerConnection: RTCPeerConnection) {
            print("sending candidate for:", candidate.sdpMid as Any, ", index:", candidate.sdpMLineIndex, "full SDP:", (peerConnection.localDescription?.sdp ?? ""));
            
            guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp) else {
                return;
            }
            guard let mid = candidate.sdpMid else {
                return;
            }
            
            guard let desc = peerConnection.localDescription, let (sdp, sid) = SDP.parse(sdpString: desc.sdp, creator: role) else {
                return;
            }
            
            guard let content = sdp.contents.first(where: { c -> Bool in
                return c.name == mid;
            }), let transport = content.transports.first(where: {t -> Bool in
                return (t as? Jingle.Transport.ICEUDPTransport) != nil;
            }) as? Jingle.Transport.ICEUDPTransport else {
                return;
            }
            
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                if (!self.transportInfo(contentName: mid, creator: self.role, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]))) {
                    self.onError(.remote_server_timeout);
                }
            }
        }
                
    }
    
}

extension JingleSessionState {
    var rawValue: String {
        switch self {
        case .accepted:
            return "accepted";
        case .created:
            return "created";
        case .initiating:
            return "initiating";
        case .terminated:
            return "terminated";
        }
    }
}
