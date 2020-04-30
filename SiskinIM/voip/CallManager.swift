//
// CallManager.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

import UIKit
import CallKit
import WebRTC
import TigaseSwift

class CallManager: NSObject, CXProviderDelegate {
    
    static let instance = CallManager();
    
    private let provider: CXProvider;
    private let callController: CXCallController;
    
    private(set) var currentCall: Call?;
    private(set) var currentConnection: RTCPeerConnection?;
    
    weak var delegate: CallManagerDelegate? {
        didSet {
            if currentCall != nil {
                delegate?.callDidStart(self);
                if let peerConnection = self.currentConnection {
                    for transceiver in peerConnection.transceivers {
                        self.peerConnection(peerConnection, didStartReceivingOn: transceiver);
                    }
                }
            }
        }
    }
    
    private var establishingSessions: [JingleManager.Session] = [];
    
    private(set) var session: JingleManager.Session?;
    
    private var localCandidates: [RTCIceCandidate] = [];
    
    private override init() {
        let config = CXProviderConfiguration(localizedName: "SiskinIM");
        config.iconTemplateImageData = UIImage(named:"appLogo")!.pngData();
        config.includesCallsInRecents = false;
        config.supportsVideo = true;
        config.maximumCallsPerCallGroup = 1;
        config.supportedHandleTypes = [.generic];

        provider = CXProvider(configuration: config);
        callController = CXCallController();
        super.init();
        provider.setDelegate(self, queue: nil);
    }
    
    private func changeCallState(_ state: Call.State) {
        currentCall?.state = state;
        delegate?.callStateChanged(self);
    }
    
    func reportIncomingCall(_ call: Call, completionHandler: @escaping(Result<Void,Error>)->Void) {
        guard self.currentCall == nil else {
            completionHandler(.failure(ErrorCondition.conflict));
            return;
        }
        
        currentCall = call;
        self.session = JingleManager.instance.session(forCall: call);
        self.session?.delegate = self;
        call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            completionHandler(.failure(ErrorCondition.not_authorized));
            return;
        }
        
        let update = CXCallUpdate();
        update.remoteHandle = CXHandle(type: .generic, value: call.jid.stringValue);
        let rosterModule: RosterModule? = XmppService.instance.getClient(for: call.account)?.modulesManager.getModule(RosterModule.ID);
        let name = rosterModule?.rosterStore.get(for: JID(call.jid))?.name ?? call.jid.stringValue;
        update.localizedCallerName = name;
        update.hasVideo = AVCaptureDevice.authorizationStatus(for: .video) == .authorized && call.media.contains(.video);
        
        provider.reportNewIncomingCall(with: call.uuid, update: update, completion: { err in
            guard let error = err else {
                self.changeCallState(.ringing);
                completionHandler(.success(Void()));
                return;
            }
            completionHandler(.failure(error));
        })
    }
    
    func reportOutgoingCall(_ call: Call, completionHandler: @escaping(Result<Void,Error>)->Void) {
        guard self.currentCall == nil else {
            completionHandler(.failure(ErrorCondition.conflict));
            return;
        }
        self.currentCall = call;
        
        let rosterModule: RosterModule? = XmppService.instance.getClient(for: call.account)?.modulesManager.getModule(RosterModule.ID);
        let name = rosterModule?.rosterStore.get(for: JID(call.jid))?.name ?? call.jid.stringValue;

        let startCallAction = CXStartCallAction(call: call.uuid, handle: CXHandle(type: .generic, value: call.jid.stringValue));
        startCallAction.isVideo = call.media.contains(.video);
        startCallAction.contactIdentifier = name;
        let transaction = CXTransaction(action: startCallAction);
        callController.request(transaction, completion: { err in
            guard let error = err else {
                self.changeCallState(.ringing);
                completionHandler(.success(Void()));
                return;
            }
            completionHandler(.failure(error));
        });
        
    }
    
    func acceptedOutgoingCall(_ call: Call, by jid: JID, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        guard let currentCall = self.currentCall, call.account == currentCall.account && call.jid == currentCall.jid && call.sid == currentCall.sid else {
            completionHandler(.failure(.item_not_found));
            return;
        }
        
        changeCallState(.connecting);
        generateLocalDescription(completionHandler: { result in
            switch result {
            case .success(let sdp):
                guard let session = self.session else {
                    completionHandler(.failure(.item_not_found));
                    return
                }
                session.initiate(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil);
                completionHandler(.success(Void()));
            case .failure(let err):
                completionHandler(.failure(err));
            }
        })
    }
    
    func declinedOutgoingCall(_ call: Call) {
        guard let currentCall = self.currentCall, call.account == currentCall.account && call.jid == currentCall.jid && call.sid == currentCall.sid else {
            return;
        }
        endCall(currentCall);
    }
    
    func terminateCall(for account: BareJID, with jid: BareJID) {
        guard let currentCall = self.currentCall, account == currentCall.account && jid == currentCall.jid else {
            return;
        }
        endCall(currentCall);
    }
    
    private(set) var localVideoSource: RTCVideoSource?;
    private(set) var localVideoTrack: RTCVideoTrack?;
    private(set) var localAudioTrack: RTCAudioTrack?;
    private(set) var localCapturer: RTCCameraVideoCapturer?;
    private(set) var localCameraDeviceID: String?;
    
    func reset() {
        currentCall = nil;
        currentConnection?.close();
        currentConnection = nil;
        if localCapturer != nil {
            localCameraDeviceID = nil;
            localCapturer?.stopCapture(completionHandler: {
                self.localCapturer = nil;
            })
        }
        self.localVideoTrack = nil;
        self.localAudioTrack = nil;
        self.localVideoSource = nil;
        self.session = nil;
        delegate?.callDidEnd(self);
        delegate = nil;
        DispatchQueue.main.async {
            for session in self.establishingSessions {
                _ = session.terminate();
            }
            self.establishingSessions.removeAll();
        }
    }
    
    func providerDidReset(_ provider: CXProvider) {
        print("provider did reset!");
        reset();
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let call = currentCall else {
            action.fail();
            reset();
            return;
        }
         
        initiateWebRTC(for: call, completionHandler: { result in
            switch result {
            case .success(_):
                self.showCallController();
                if let peerConnection = self.currentConnection {
                    peerConnection.offer(for: VideoCallController.defaultCallConstraints, completionHandler: { sdpOffer, error in
                        guard sdpOffer != nil else {
                            action.fail();
                            return;
                        }
                        print("generated local description:", sdpOffer!.sdp);
                        let (sdp, sid) = SDP.parse(sdpString: sdpOffer!.sdp, creator: .initiator)!;
                        call.webrtcSid = sid;
                        peerConnection.setLocalDescription(RTCSessionDescription(type: .offer, sdp: sdp.toString(withSid: sid)), completionHandler: { err in
                            if err == nil {
                                action.fulfill();
                                // here we need to intiate JingleSession(s)
                                DispatchQueue.main.async {
                                    self.initiateSignaling(sdp, completionHandler: { result in
                                        print("stated session establishment with result:", result);
                                    });
                                }
                            } else {
                                action.fail();
                            }
                        })
                    })
                } else {
                    action.fail();
                }
            case .failure(_):
                action.fail();
            }
        })
    }
    
    private func initiateSignaling(_ sdp: SDP, completionHandler: (Result<Void,Error>)->Void) {
        guard let call = self.currentCall, let client = XmppService.instance.getClient(for: call.account), let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        }
        
        guard let presences = presenceModule.presenceStore.getPresences(for: call.jid)?.values, !presences.isEmpty else {
            provider.reportCall(with: call.uuid, endedAt: Date(), reason: .failed);
            completionHandler(.failure(ErrorCondition.internal_server_error));
            return;
        }
       
        var withJingle: [JID] = [];
        var withJMI: [JID] = [];
        for presence in presences {
            if let jid = presence.from, let capsNode = presence.capsNode {
                if let features = DBCapabilitiesCache.instance.getFeatures(for: capsNode) {
                    if features.contains(JingleModule.XMLNS) && features.contains(Jingle.Transport.ICEUDPTransport.XMLNS) && features.contains("urn:xmpp:jingle:apps:rtp:audio") {
                        withJingle.append(jid);
                        if features.contains(JingleModule.MESSAGE_INITIATION_XMLNS) {
                            withJMI.append(jid);
                        }
                    }
                }
            }
        }
        guard !withJingle.isEmpty else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        }
                
        if withJMI.count == withJingle.count {
            let session = JingleManager.instance.open(for: client.sessionObject, with: JID(call.jid), sid: call.sid, role: .initiator, initiationType: .message);
            session.delegate = self;
            session.initiate(descriptions: call.media.map({ Jingle.MessageInitiationAction.Description(xmlns: "urn:xmpp:jingle:apps:rtp:1", media: $0.rawValue) }), completionHandler: nil);
        } else {
            // we need to establish multiple 1-1 sessions...
            self.generateLocalDescription(completionHandler: { result in
                switch result {
                case .failure(_):
                    self.reset();
                case .success(let sdp):
                    for jid in withJingle {
                        let session = JingleManager.instance.open(for: client.sessionObject, with: jid, sid: call.sid, role: .initiator, initiationType: .iq);
                        session.delegate = self;
                        self.establishingSessions.append(session);
                        session.initiate(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil);
                    }
                }
            })
        }
    }
    
    private func generateLocalDescription(completionHandler: @escaping (Result<SDP,ErrorCondition>)->Void) {
        if let peerConnection = self.currentConnection {
            peerConnection.offer(for: VideoCallController.defaultCallConstraints, completionHandler: { (description, error) in
                guard let desc = description, let (sdp, sid) = SDP.parse(sdpString: desc.sdp, creator: .initiator) else {
                    completionHandler(.failure(.internal_server_error));
                    return;
                }
                peerConnection.setLocalDescription(RTCSessionDescription(type: desc.type, sdp: sdp.toString(withSid: self.currentCall!.webrtcSid!)), completionHandler: { error in
                    guard error == nil else {
                        completionHandler(.failure(.internal_server_error));
                        return;
                    }
                    completionHandler(.success(sdp));
                })
            })
        } else {
            completionHandler(.failure(.item_not_found));
        }
    }
    
    private func initiateWebRTC(for call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        currentConnection = VideoCallController.initiatePeerConnection(withDelegate: self);
        if currentConnection != nil {
            self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
            if let localAudioTrack = self.localAudioTrack {
                currentConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
            }
            if call.media.contains(.video) && AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                let videoSource = VideoCallController.peerConnectionFactory.videoSource();
                self.localVideoSource = videoSource;
                let localVideoTrack = VideoCallController.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video-" + UUID().uuidString);
                self.localVideoTrack = localVideoTrack;
                let localVideoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                self.localCapturer = localVideoCapturer;
                currentConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                if let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }), let format = RTCCameraVideoCapturer.format(for: device, preferredOutputPixelFormat: localVideoCapturer.preferredOutputPixelFormat()) {
                    print("starting video capture on:", device, " with:", format, " fps:", RTCCameraVideoCapturer.fps(for: format));
                    self.localCameraDeviceID = device.uniqueID;
                    DispatchQueue.main.async {
                        localVideoCapturer.startCapture(with: device, format: format, fps: RTCCameraVideoCapturer.fps(for:  format), completionHandler: { error in
                            print("video capturer started!");
                            DispatchQueue.main.async {
                                completionHandler(.success(Void()));
                            }
                        });
                        self.delegate?.callManager(self, didReceiveLocalVideoCapturer: localVideoCapturer);
                    }
                }
            } else {
                completionHandler(.success(Void()));
            }
        } else {
            completionHandler(.failure(ErrorCondition.internal_server_error));
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = currentCall else {
            action.fail();
            reset();
            return;
        }

        guard let session = self.session else {
            action.fail();
            self.reset();
            return;
        }
        
        self.changeCallState(.connecting)
        
        initiateWebRTC(for: call, completionHandler: { result in
            switch result {
            case .success(_):
                let avsession = AVAudioSession.sharedInstance()

                do {
                    try avsession.setCategory(.playAndRecord, mode: .videoChat)
                    try avsession.setPreferredIOBufferDuration(0.005)
                    try avsession.setPreferredSampleRate(4_410)
                } catch {
                    fatalError(error.localizedDescription)
                }
                
                self.showCallController();
                
                session.delegate = self;

                action.fulfill();
                session.accept();
            case .failure(_):
                action.fail();
            }
        })
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let wasAccepted = self.currentConnection != nil;
        let session = self.session;
        self.reset();
        if wasAccepted {
            _ = session?.terminate();
        } else {
            _ = session?.decline();
        }
        delegate?.callDidEnd(self);
        action.fulfill();
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        localAudioTrack?.isEnabled = !action.isMuted;
        action.fulfill();
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        print("operation timed out!");
    }
    
    private func showCallController() {
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }

        let controller = UIStoryboard(name: "VoIP", bundle: nil).instantiateViewController(withIdentifier: "VideoCallController") as! VideoCallController;
        self.delegate = controller;
        topController?.show(controller, sender: self);
    }
    
    func switchCameraDevice() {
        if let localCapturer = self.localCapturer, let deviceID = self.localCameraDeviceID {
            let position = RTCCameraVideoCapturer.captureDevices().first(where: { $0.uniqueID == deviceID })?.position ?? .front;
            if let newCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position != position }), let format = RTCCameraVideoCapturer.format(for: newCamera, preferredOutputPixelFormat: localCapturer.preferredOutputPixelFormat()) {
                self.localCameraDeviceID = newCamera.uniqueID;
                localCapturer.startCapture(with: newCamera, format: format, fps: RTCCameraVideoCapturer.fps(for: format));
            }
        }
    }
    
    func muteCall(_ call: Call, value: Bool) {
        guard let c = self.currentCall, c == call else {
            return;
        }
        
        let muteCallAction = CXSetMutedCallAction(call: call.uuid, muted: value);
        callController.request(CXTransaction(action: muteCallAction), completion: { error in
            if let error = error {
                fatalError(error.localizedDescription)
            }
        });
    }
    
    func endCall(_ call: Call) {
        guard let c = self.currentCall, c == call else {
            return;
        }
        
        DispatchQueue.main.async {
            self.changeCallState(.ended)
        }
        
        let endCallAction = CXEndCallAction(call: call.uuid);
        let transaction = CXTransaction(action: endCallAction);
        callController.request(transaction) { error in
            if let error = error {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    fileprivate func setRemoteDescription(_ remoteDescription: SDP, call: Call, peerConnection: RTCPeerConnection, session: JingleManager.Session, completionHandler: @escaping (Result<Void,Error>)->Void) {
        print("setting remote description");
        peerConnection.setRemoteDescription(RTCSessionDescription(type: call.direction == .incoming ? .offer : .answer, sdp: remoteDescription.toString(withSid: call.webrtcSid!)), completionHandler: { error in
            if let err = error {
                print("failed to set remote description!", err);
                completionHandler(.failure(err));
            } else if call.direction == .incoming {
                //DispatchQueue.main.async {
                print("retrieving current connection");
//                peerConnection.transceivers.forEach({ transceiver in
//                    if (!call.media.contains(.audio)) && transceiver.mediaType == .audio {
//                        transceiver.stop();
//                    }
//                    if (!call.media.contains(.video)) && transceiver.mediaType == .video {
//                        transceiver.stop();
//                    }
//                });
                print("generating answer");
                peerConnection.answer(for: VideoCallController.defaultCallConstraints, completionHandler: { (sdpAnswer, error) in
                    if let err = error {
                        print("answer generation failed:", err);
                        completionHandler(.failure(err));
                    } else {
                        print("setting local description:", sdpAnswer!.sdp);
                        peerConnection.setLocalDescription(sdpAnswer!, completionHandler: { error in
                            if let err = error {
                                print("answer generation failed:", err);
                                completionHandler(.failure(err));
                            } else {
                                print("sending answer to remote client");
                                let (sdp, sid) = SDP.parse(sdpString: sdpAnswer!.sdp, creator: .responder)!;
                                _ = session.accept(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                                    self.sendLocalCandidates();
                                })
                                completionHandler(.success(Void()));
                            }
                        });
                    }
                })
                //}
            } else {
                completionHandler(.success(Void()));
            }
        })
    }
}

class Call: Equatable {
    static func == (lhs: Call, rhs: Call) -> Bool {
        return lhs.account == rhs.account && lhs.jid == rhs.jid && lhs.uuid == rhs.uuid;
    }
    
    
    let account: BareJID;
    let jid: BareJID;
    let uuid: UUID;
    
    let direction: Direction;
    let sid: String;
    let media: [Media]
    
    var state: State = .new;
    
    fileprivate var webrtcSid: String?;
    
    init(account: BareJID, with jid: BareJID, sid: String, direction: Direction, media: [Media]) {
        self.uuid = UUID();
        self.account = account;
        self.jid = jid;
        self.media = media;
        self.sid = sid;
        self.direction = direction;
    }
    
    enum Media: String {
        case audio
        case video
        
        static func from(string: String?) -> Media? {
            guard let v = string else {
                return nil;
            }
            return Media(rawValue: v);
        }
        
        var avmedia: AVMediaType {
            switch self {
            case .audio:
                return .audio
            case .video:
                return .video;
            }
        }
    }

    enum Direction {
        case incoming
        case outgoing
    }
    
    enum State {
        case new
        case ringing
        case connecting
        case connected
        case ended
    }

}

protocol CallManagerDelegate: class {
    
    func callDidStart(_ sender: CallManager);
    func callDidEnd(_ sender: CallManager);
    func callStateChanged(_ sender: CallManager);
    
    func callManager(_ sender: CallManager, didReceiveLocalVideoCapturer localCapturer: RTCCameraVideoCapturer);
    func callManager(_ sender: CallManager, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack);

    
}

extension CallManager: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("signaling state:", stateChanged.rawValue);
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .disconnected:
            guard let call = self.currentCall else {
                return;
            }
            self.endCall(call);
        case .connected:
            DispatchQueue.main.async {
                self.changeCallState(.connected);
            }
        default:
            break;
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        JingleManager.instance.dispatcher.async {
            self.localCandidates.append(candidate);
            self.sendLocalCandidates();
        }
    }
    
    private func sendLocalCandidates() {
        guard let session = self.session, let peerConnection = self.currentConnection else {
            return;
        }
        for candidate in localCandidates {
            session.sendLocalCandidate(candidate, peerConnection: peerConnection);
        }
        self.localCandidates = [];
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if transceiver.direction == .recvOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                print("got video transceiver");
                guard let track = transceiver.receiver.track as? RTCVideoTrack else {
                    return;
                }
                self.delegate?.callManager(self, didReceiveRemoteVideoTrack: track)
            }
        }
        if transceiver.direction == .sendOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                guard let track = transceiver.sender.track as? RTCVideoTrack else {
                    return;
                }
                // FIXME: What to do here?
//                self.delegate?.didAdd(localVideoTrack: track);
            }
        }

    }
    
}

extension CallManager: JingleSessionDelegate {
    
    func session(_ session: JingleManager.Session, setRemoteDescription sdp: SDP) {
        DispatchQueue.main.async {
            print("peer connection:", self.currentConnection, self.currentCall, self.currentCall?.sid, session.sid)
            guard let peerConnection = self.currentConnection, let call = self.currentCall, call.account == session.account && call.sid == session.sid && call.jid == session.jid.bareJid else {
                return;
            }
            
            for sess in self.establishingSessions {
                if sess.account == session.account && sess.jid == session.jid && sess.sid == session.sid {
                    self.session = sess;
                    self.sendLocalCandidates();
                } else {
                    _ = sess.terminate();
                }
            }
            self.establishingSessions.removeAll();
            
            self.changeCallState(.connecting);
            
            self.setRemoteDescription(sdp, call: call, peerConnection: peerConnection, session: session, completionHandler: { result in
                switch result {
                case .success(_):
                    break;
                case .failure(let err):
                    print("error setting remote description:", err)
                    self.provider.reportCall(with: call.uuid, endedAt: Date(), reason: .failed);
                }
            })
        }
    }
    
    func sessionTerminated(session: JingleManager.Session) {
        DispatchQueue.main.async {
            guard let call = self.currentCall, call.account == session.account && call.sid == session.sid && call.jid == session.jid.bareJid else {
                return;
            }
            
            if call.direction == .outgoing {
                if let idx = self.establishingSessions.firstIndex(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid }) {
                    self.establishingSessions.remove(at: idx);
                }
                if self.establishingSessions.isEmpty {
                    self.provider.reportCall(with: call.uuid, endedAt: Date(), reason: .remoteEnded);
                    self.reset();
                }
            } else {
                self.provider.reportCall(with: call.uuid, endedAt: Date(), reason: .remoteEnded);
                self.reset();
            }
        }
    }
    
    func session(_ session: JingleManager.Session, didReceive candidate: RTCIceCandidate) {
        guard let peerConnection = currentConnection else {
            return;
        }
        peerConnection.add(candidate)
    }
    
    
}
