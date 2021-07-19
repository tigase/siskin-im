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
import PushKit
import WebRTC
import TigaseSwift  
import Shared
import Combine

class CallManager: NSObject, CXProviderDelegate {    
    
    static var isAvailable: Bool {
        let userLocale = NSLocale.current

        if (userLocale.regionCode?.contains("CN") ?? false) ||
            (userLocale.regionCode?.contains("CHN") ?? false) {

            return false
        } else {
            return true
        }
    }
    
    private(set) static var instance: CallManager? = nil;
    
    static func initializeCallManager() {
        if isAvailable {
            if instance == nil {
                instance = CallManager();
            }
        } else {
            instance = nil;
        }
    }
    
    private let pushRegistry: PKPushRegistry;
    
    private let provider: CXProvider;
    private let callController: CXCallController;
    
//    private(set) var currentCall: Call?;
//    private(set) var currentConnection: RTCPeerConnection?;
    
//    weak var delegate: CallManagerDelegate? {
//        didSet {
//            if currentCall != nil {
//                delegate?.callDidStart(self);
//                if let peerConnection = self.currentConnection {
//                    for transceiver in peerConnection.transceivers {
//                        self.peerConnection(peerConnection, didStartReceivingOn: transceiver);
//                    }
//                }
//            }
//        }
//    }
    
//    private var establishingSessions: [JingleManager.Session] = [];
//
//    private(set) var session: JingleManager.Session?;
//
//    private var localCandidates: [RTCIceCandidate] = [];
    
    private let dispatcher = QueueDispatcher(label: "CallManager");
    @Published
    private var activeCalls: [Call.Key: Call] = [:];
    private var activeCallsByUuid: [UUID: Call] = [:];
    private var cancellables: Set<AnyCancellable> = [];
    
    private override init() {
        let config = CXProviderConfiguration(localizedName: "SiskinIM");
        if #available(iOS 13.0, *) {
            if let image = UIImage(systemName: "message.fill") {
                config.iconTemplateImageData = image.pngData();
            }
        } else {
            if let image = UIImage(named: "message.fill") {
                config.iconTemplateImageData = image.pngData();
            }
        }
        config.includesCallsInRecents = false;
        config.supportsVideo = true;
        config.maximumCallsPerCallGroup = 1;
        config.maximumCallGroups = 1;
        config.supportedHandleTypes = [.generic];

        provider = CXProvider(configuration: config);
        callController = CXCallController();
        pushRegistry = PKPushRegistry(queue: nil);
        super.init();
        provider.setDelegate(self, queue: nil);
        
        pushRegistry.delegate = self;
        pushRegistry.desiredPushTypes = [.voIP];
        $activeCalls.map({ !$0.isEmpty }).assign(to: \.onCall, on: XmppService.instance).store(in: &cancellables);
        $activeCalls.map({ !$0.isEmpty }).sink(receiveValue: { callInProgress in
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = callInProgress;
            }
        }).store(in: &cancellables);
        
    }
    
//    private func changeCallState(_ state: Call.State) {
//        currentCall?.state = state;
//        delegate?.callStateChanged(self);
//    }
    
    func reportIncomingCall(_ call: Call, completionHandler: @escaping(Result<Void,Error>)->Void) {
        dispatcher.async {
            guard self.activeCalls[call.key] == nil else {
                completionHandler(.failure(XMPPError.conflict("Call already registered!")));
                return;
            }
            self.activeCalls[call.key] = call;
                    
            let update = CXCallUpdate();
            update.remoteHandle = CXHandle(type: .generic, value: call.jid.stringValue);
            let name = DBRosterStore.instance.item(for: call.account, jid: JID(call.jid))?.name ?? call.jid.stringValue;
            update.localizedCallerName = name;
            update.hasVideo = AVCaptureDevice.authorizationStatus(for: .video) == .authorized && call.media.contains(.video);
            
            call.session = JingleManager.instance.session(forCall: call);
            print("reporting incoming call: \(call.uuid)")
            self.provider.reportNewIncomingCall(with: call.uuid, update: update, completion: { err in
                guard let error = err else {
                    self.activeCallsByUuid[call.uuid] = call;
                    self.dispatcher.sync {
                        call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
                        call.changeState(.ringing);
                    }
                    completionHandler(.success(Void()));
                    return;
                }

                self.activeCalls.removeValue(forKey: call.key);
                
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                    completionHandler(.failure(ErrorCondition.not_authorized));
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: { _ in });
                    if call.media.contains(.video) {
                        AVCaptureDevice.requestAccess(for: .video, completionHandler: { _ in });
                    }
                    return;
                }

                completionHandler(.failure(error));
            })
        }
    }
    
    func reportOutgoingCall(_ call: Call, completionHandler: @escaping(Result<Void,Error>)->Void) {
        dispatcher.async {
            guard self.activeCalls[call.key] == nil else {
                completionHandler(.failure(XMPPError.conflict("Call already registered!")));
                return;
            }
            self.activeCalls[call.key] = call;

            let name = DBRosterStore.instance.item(for: call.account, jid: JID(call.jid))?.name ?? call.jid.stringValue;
            let startCallAction = CXStartCallAction(call: call.uuid, handle: CXHandle(type: .generic, value: call.jid.stringValue));
            startCallAction.isVideo = call.media.contains(.video);
            startCallAction.contactIdentifier = name;
            let transaction = CXTransaction(action: startCallAction);
            print("reporting outgoing call: \(call.uuid)")
            self.callController.request(transaction, completion: { err in
                guard let error = err else {
                    self.activeCallsByUuid[call.uuid] = call;
                    call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
                    call.changeState(.ringing);
                    completionHandler(.success(Void()));
                    return;
                }
                completionHandler(.failure(error));
            });
        }
    }
    
//    func acceptedOutgoingCall(_ call: Call, by jid: JID, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
//        call.changeState(.connecting);
//        if call.session == nil {
//            call.session = JingleManager.instance.session(forCall: call);
//        }
//        generateLocalDescription(completionHandler: { result in
//            switch result {
//            case .success(let sdp):
//                guard let session = self.session else {
//                    completionHandler(.failure(.item_not_found));
//                    return
//                }
//                session.initiate(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil);
//                completionHandler(.success(Void()));
//            case .failure(let err):
//                completionHandler(.failure(err));
//            }
//        })
//    }
//
//    func declinedOutgoingCall(_ call: Call) {
//        guard let currentCall = self.currentCall, call.account == currentCall.account && call.jid == currentCall.jid && call.sid == currentCall.sid else {
//            return;
//        }
//        endCall(currentCall);
//    }
//
//    func terminateCall(for account: BareJID, with jid: BareJID) {
//        guard let currentCall = self.currentCall, account == currentCall.account && jid == currentCall.jid else {
//            return;
//        }
//        endCall(currentCall);
//    }
//
//    private(set) var localVideoSource: RTCVideoSource?;
//    private(set) var localVideoTrack: RTCVideoTrack?;
//    private(set) var localAudioTrack: RTCAudioTrack?;
//    private(set) var localCapturer: RTCCameraVideoCapturer?;
//    private(set) var localCameraDeviceID: String?;
    
//    func reset() {
//        print("resetting call manager");
//        DispatchQueue.main.async {
//            UIApplication.shared.isIdleTimerDisabled = false;
//        }
//        currentCall = nil;
//        currentConnection?.close();
//        currentConnection = nil;
//        if localCapturer != nil {
//            localCameraDeviceID = nil;
//            localCapturer?.stopCapture(completionHandler: {
//                self.localCapturer = nil;
//            })
//        }
//        self.localVideoTrack = nil;
//        self.localAudioTrack = nil;
//        self.localVideoSource = nil;
//        self.session = nil;
//        delegate?.callDidEnd(self);
//        delegate = nil;
//        DispatchQueue.main.async {
//            for session in self.establishingSessions {
//                _ = session.terminate();
//            }
//            self.establishingSessions.removeAll();
//            (UIApplication.shared.delegate as? AppDelegate)?.initiateBackgroundTask();
//        }
//        XmppService.instance.onCall = false;
//    }
    
    func providerDidReset(_ provider: CXProvider) {
        print("provider did reset!");
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let call = activeCallsByUuid[action.callUUID] else {
            action.fail();
            return;
        }
        DispatchQueue.main.async {
            self.showCallController(completionHandler: { controller in
                call.delegate = controller;
            });
        }
        call.initiateOutgoingCall(completionHandler: { result in
            switch result {
            case .success(_):
                action.fulfill(withDateStarted: Date());
            case .failure(let err):
                action.fail();
                call.reset();
            }
        })
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = activeCallsByUuid[action.callUUID] else {
            action.fail();
            return;
        }
        
        // here we should wait till XMPPClient is connected..
        DispatchQueue.main.async {
            self.accountConnected = { account in
                guard XmppService.instance.getClient(for: call.account)?.state == .connected() else {
                    return;
                }
                self.accountConnected = nil;
                call.accept();
                action.fulfill();

                self.showCallController(completionHandler: { controller in
                    call.delegate = controller;
                });
            }
            
            self.connectionEstablished(for: call.account);
        }
    }
    
    private var accountConnected: ((BareJID)->Void)?;
    
    func connectionEstablished(for account: BareJID) {
        DispatchQueue.main.async {
            self.accountConnected?(account);
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let call = activeCallsByUuid[action.callUUID] else {
            action.fail();
            return;
        }

        if call.state == .new || call.state == .ringing {
            call.reject();
        } else {
            call.reset();
        }
        action.fulfill();
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = activeCallsByUuid[action.callUUID] else {
            action.fail();
            return;
        }

        call.muted(value: action.isMuted);
        action.fulfill();
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        print("operation timed out!");
    }
    
    private func showCallController(completionHandler: (VideoCallController)->Void) {
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }

        let controller = UIStoryboard(name: "VoIP", bundle: nil).instantiateViewController(withIdentifier: "VideoCallController") as! VideoCallController;
        topController?.show(controller, sender: self);
        completionHandler(controller);
    }
        
    func muteCall(_ call: Call, value: Bool) {
        let muteCallAction = CXSetMutedCallAction(call: call.uuid, muted: value);
        callController.request(CXTransaction(action: muteCallAction), completion: { error in
            if let error = error {
                fatalError(error.localizedDescription)
            }
        });
    }
    
    func endCall(_ call: Call) {
        let endCallAction = CXEndCallAction(call: call.uuid);
        let transaction = CXTransaction(action: endCallAction);
        callController.request(transaction) { error in
            if let error = error {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    func endCall(on account: BareJID, with jid: BareJID,  sid: String, completionHandler: @escaping ()->Void) {
        print("endCall(on account) called");
        dispatcher.async {
            guard let call = self.activeCalls[.init(account: account, jid: jid, sid: sid)] else {
                completionHandler();
                return;
            }
            let endCallAction = CXEndCallAction(call: call.uuid);
            let transaction = CXTransaction(action: endCallAction);
            self.callController.request(transaction) { error in
                call.reset();
                completionHandler();
            }
        }
    }

}

class Call: NSObject, JingleSessionActionDelegate {
    static func == (lhs: Call, rhs: Call) -> Bool {
        return lhs.key == rhs.key;
    }
    
    
    struct Key: Hashable {
        let account: BareJID;
        let jid: BareJID;
        let sid: String;
    }
    
    let key: Key;
    let uuid: UUID;
    var account: BareJID {
        return key.account;
    }
    var jid: BareJID {
        return key.jid;
    }
    var sid: String {
        return key.sid;
    }

    let direction: Direction;
    let media: [Media]
    
    private(set) var state: State = .new;
    
    var webrtcSid: String?;
    
    private(set) var currentConnection: RTCPeerConnection?;
    
    fileprivate(set) weak var delegate: CallDelegate? {
        didSet {
            delegate?.callDidStart(self);
        }
    }
    fileprivate(set) var session: JingleManager.Session? {
        didSet {
            session?.$state.removeDuplicates().sink(receiveValue: { [weak self] state in
                guard let that = self else {
                    return;
                }
                switch state {
                case .accepted:
                    switch that.direction {
                    case .incoming:
                        break;
                    case .outgoing:
                        that.acceptedOutgingCall();
                    }
                case .terminated:
                    that.sessionTerminated()
                default:
                    break;
                }
            }).store(in: &cancellables);
        }
    }

    private var establishingSessions: [JingleManager.Session] = [];
    
    private var localCandidates: [RTCIceCandidate] = [];
    
    private(set) var localVideoSource: RTCVideoSource?;
    private(set) var localVideoTrack: RTCVideoTrack?;
    private(set) var localAudioTrack: RTCAudioTrack?;
    private(set) var localCapturer: RTCCameraVideoCapturer?;
    private(set) var localCameraDeviceID: String?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    init(account: BareJID, with jid: BareJID, sid: String, direction: Direction, media: [Media]) {
        self.key = .init(account: account, jid: jid, sid: sid);
        self.uuid = UUID();
        self.media = media;
        self.direction = direction;
    }
    
    func reset() {
         DispatchQueue.main.async {
             self.currentConnection?.close();
             self.currentConnection = nil;
             if self.localCapturer != nil {
                 self.localCapturer?.stopCapture(completionHandler: {
                     self.localCapturer = nil;
                 })
             }
             self.localVideoTrack = nil;
             self.localAudioTrack = nil;
             self.localVideoSource = nil;
             self.delegate?.callDidEnd(self);
             _ = self.session?.terminate();
             self.session = nil;
             self.delegate = nil;
             for session in self.establishingSessions {
                 session.terminate();
             }
             self.establishingSessions.removeAll();
             self.state = .ended;
         }
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

    func initiateOutgoingCall(with callee: JID? = nil, completionHandler: @escaping (Result<Void,Error>)->Void) {
        guard let client = XmppService.instance.getClient(for: account) else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        }
        var withJingle: [JID] = [];
        var withJMI: [JID] = [];
        
        if let jid = callee {
            withJingle.append(jid);
        } else {
            let presences = PresenceStore.instance.presences(for: jid, context: client);
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
        }
                
        self.changeState(.ringing);
        initiateWebRTC(completionHandler: { result in
            switch result {
            case .success(_):
                completionHandler(.success(Void()));
                if withJMI.count == withJingle.count {
                    let session = JingleManager.instance.open(for: client, with: JID(self.jid), sid: self.sid, role: .initiator, initiationType: .message);
                    self.session = session;
                    _ = session.initiate(descriptions: self.media.map({ Jingle.MessageInitiationAction.Description(xmlns: "urn:xmpp:jingle:apps:rtp:1", media: $0.rawValue) }));
                } else {
                    // we need to establish multiple 1-1 sessions...
                    guard let peerConnection = self.currentConnection else {
                        return;
                    }
                    self.generateOfferAndSet(peerConnection: peerConnection, completionHandler: { result in
                        switch result {
                        case .failure(_):
                            self.reset();
                        case .success(let sdp):
                            DispatchQueue.main.async {
                                for jid in withJingle {
                                    let session = JingleManager.instance.open(for: client, with: jid, sid: self.sid, role: .initiator, initiationType: .iq);
                                    session.$state.removeDuplicates().receive(on: DispatchQueue.main).sink(receiveValue: { state in
                                        switch state {
                                        case .accepted:
                                            guard self.session == nil else {
                                                session.terminate();
                                                return;
                                            }
                                            for sess in self.establishingSessions {
                                                if sess.account == session.account && sess.jid == session.jid && sess.sid == session.sid {
                                                } else {
                                                    sess.terminate();
                                                }
                                            }
                                            self.establishingSessions.removeAll();
                                            self.session = session;
                                            self.state = .connecting;
                                            self.connectRemoteSDPPublishers(session: session);
                                            self.sendLocalCandidates();
                                        case .terminated:
                                            if let idx = self.establishingSessions.firstIndex(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid }) {
                                                self.establishingSessions.remove(at: idx);
                                            }
                                            if self.establishingSessions.isEmpty && self.session == nil {
                                                self.reset();
                                            }
                                        default:
                                            break;
                                        }
                                    }).store(in: &self.cancellables);
                                    self.establishingSessions.append(session);
                                    _ = session.initiate(contents: sdp.contents, bundle: sdp.bundle);
                                }
                            }
                        }
                    })
                }
            case .failure(let err):
                completionHandler(.failure(err));
            }
        })
    }
        
    private func acceptedOutgingCall() {
        guard let session = session, session.initiationType == .message, state == .ringing, let peerConnection = self.currentConnection else {
            return;
        }
        changeState(.connecting);
        generateOfferAndSet(peerConnection: peerConnection, completionHandler: { result in
            switch result {
            case .success(let sdp):
                guard let session = self.session else {
                    self.reset();
                    return
                }
                self.connectRemoteSDPPublishers(session: session);
                _ = session.initiate(contents: sdp.contents, bundle: sdp.bundle);
            case .failure(_):
                self.reset();
            }
        });
    }
    
    private func connectRemoteSDPPublishers(session: JingleManager.Session) {
        session.setDelegate(self);
    }
        
    static let VALID_SERVICE_TYPES = ["stun", "stuns", "turn", "turns"];
    
    func initiateWebRTC(completionHandler: @escaping (Result<Void,Error>)->Void) {
        if let module: ExternalServiceDiscoveryModule = XmppService.instance.getClient(for: self.account)?.module(.externalServiceDiscovery), module.isAvailable {
            module.discover(from: nil, type: nil, completionHandler: { result in
                switch result {
                case .success(let services):
                    var servers: [RTCIceServer] = [];
                    for service in services {
                        if let server = service.rtcIceServer() {
                            servers.append(server);
                        }
                    }
                    self.initiateWebRTC(iceServers: servers, completionHandler: completionHandler);
                case .failure(_):
                    self.initiateWebRTC(iceServers: [], completionHandler: completionHandler);
                }
            })
        } else {
            initiateWebRTC(iceServers: [], completionHandler: completionHandler);
        }
    }
    
    private func initiateWebRTC(iceServers: [RTCIceServer], completionHandler: @escaping (Result<Void,Error>)->Void) {
        self.currentConnection = VideoCallController.initiatePeerConnection(iceServers: iceServers, withDelegate: self);
        if self.currentConnection != nil {
            let avsession = AVAudioSession.sharedInstance()

            do {
                try avsession.setCategory(.playAndRecord, mode: .videoChat)
                try avsession.setPreferredIOBufferDuration(0.005)
                try avsession.setPreferredSampleRate(4_410)
            } catch {
                fatalError(error.localizedDescription)
            }

            self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
            if let localAudioTrack = self.localAudioTrack {
                self.currentConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
            }
            if self.media.contains(.video) && AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                let videoSource = VideoCallController.peerConnectionFactory.videoSource();
                self.localVideoSource = videoSource;
                let localVideoTrack = VideoCallController.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video-" + UUID().uuidString);
                self.localVideoTrack = localVideoTrack;
                let localVideoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                self.localCapturer = localVideoCapturer;
                
                if let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }), let format = RTCCameraVideoCapturer.format(for: device, preferredOutputPixelFormat: localVideoCapturer.preferredOutputPixelFormat()) {
                    print("starting video capture on:", device, " with:", format, " fps:", RTCCameraVideoCapturer.fps(for: format));
                    self.localCameraDeviceID = device.uniqueID;
                    localVideoCapturer.startCapture(with: device, format: format, fps: RTCCameraVideoCapturer.fps(for:  format), completionHandler: { error in
                        print("video capturer started!");

                    });
                    self.delegate?.call(self, didReceiveLocalVideoTrack: localVideoTrack);
                    self.currentConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                    completionHandler(.success(Void()));
                } else {
                    completionHandler(.failure(ErrorCondition.not_authorized));
                }
            } else {
                completionHandler(.success(Void()));
            }
        } else {
            completionHandler(.failure(ErrorCondition.internal_server_error));
        }
    }

    func accept() {
        guard let session = self.session else {
            reset();
            return;
        }
        changeState(.connecting);
        initiateWebRTC(completionHandler: { result in
            switch result {
            case .success(_):
                guard self.currentConnection != nil else {
                    self.reject();
                    return;
                }
                session.accept();
                self.connectRemoteSDPPublishers(session: session);
            case .failure(_):
                // there was an error, so we should reject this call
                self.reject();
            }
        })
    }
    
    func reject() {
        guard let session = self.session else {
            reset();
            return;
        }
        session.decline();
        reset();
    }
    
    private var localSessionDescription: SDP?;
    private var remoteSessionDescription: SDP?;
    
    private let remoteSessionSemaphore = DispatchSemaphore(value: 1);
    
    public func received(action: JingleManager.Session.Action) {
        guard let peerConnection = self.currentConnection, let session = self.session else {
            return;
        }
        
            
        remoteSessionSemaphore.wait();
            
        if case let .transportAdd(candidate, contentName) = action {
            if let idx = remoteSessionDescription?.contents.firstIndex(where: { $0.name == contentName }) {
                peerConnection.add(RTCIceCandidate(sdp: candidate.toSDP(), sdpMLineIndex: Int32(idx), sdpMid: contentName));
            }
            remoteSessionSemaphore.signal();
            return;
        }
            
        let result = apply(action: action, on: self.remoteSessionDescription);
            
        guard let newSDP = result else {
            remoteSessionSemaphore.signal();
            return;
        }
            
        let prevLocalSDP = self.localSessionDescription;
        setRemoteDescription(newSDP, peerConnection: peerConnection, completionHandler: { result in
            self.remoteSessionSemaphore.signal();
            switch result {
            case .failure(let error):
                print("error setting remote description:", error)
                self.reset();
            case .success(let localSDP):
                if let sdp = localSDP {
                    if prevLocalSDP != nil {
                        let changes = sdp.diff(from: prevLocalSDP!);
                        if let addSDP = changes[.add] {
                            _ = session.contentModify(action: .accept, contents: addSDP.contents, bundle: addSDP.bundle);
                        }
                        if let modifySDP = changes[.modify] {
                            // can we safely ignore this?
                        }
                    } else {
                        _ = session.accept(contents: sdp.contents, bundle: sdp.bundle)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                            self.sendLocalCandidates();
                        })
                    }
                }
                break;
            }
        });
    }
        
    private func apply(action: JingleManager.Session.Action, on prevSDP: SDP?) -> SDP? {
        switch action {
        case .contentSet(let newSDP):
            return newSDP;
        case .contentApply(let action, let diffSDP):
            switch action {
            case .add, .accept, .remove, .modify:
                return prevSDP?.applyDiff(action: action, diff: diffSDP);
            }
        case .transportAdd(_, _):
            return nil;
        }
    }
    
    private func setRemoteDescription(_ remoteDescription: SDP, peerConnection: RTCPeerConnection, completionHandler: @escaping (Result<SDP?,Error>)->Void) {
        print("setting remote description", remoteDescription.toString(withSid: ""));
        peerConnection.setRemoteDescription(RTCSessionDescription(type: self.direction == .incoming ? .offer : .answer, sdp: remoteDescription.toString(withSid: self.webrtcSid!)), completionHandler: { err in
            guard let error = err else {
                self.remoteSessionDescription = remoteDescription;
                if peerConnection.signalingState == .haveRemoteOffer {
                    self.generateAnswerAndSet(peerConnection: peerConnection, completionHandler: { result in
                        switch result {
                        case .success(let localSDP):
                            completionHandler(.success(localSDP));
                        case .failure(let error):
                            completionHandler(.failure(error));
                        }
                    })
                } else {
                    completionHandler(.success(nil));
                }
                return;
            }
            completionHandler(.failure(error));
        });
    }
    
    private func generateOfferAndSet(peerConnection: RTCPeerConnection, completionHandler: @escaping (Result<SDP,Error>)->Void) {
        print("generating offer");
        peerConnection.offer(for: VideoCallController.defaultCallConstraints, completionHandler: { sdpOffer, err in
            guard let error = err else {
                self.setLocalDescription(peerConnection: peerConnection, sdp: sdpOffer!, completionHandler: completionHandler);
                return;
            }
            completionHandler(.failure(error));
        });
    };
        
    private func generateAnswerAndSet(peerConnection: RTCPeerConnection, completionHandler: @escaping (Result<SDP,Error>)->Void) {
        print("generating answer");
        peerConnection.answer(for: VideoCallController.defaultCallConstraints, completionHandler: { sdpAnswer, err in
            guard let error = err else {
                self.setLocalDescription(peerConnection: peerConnection, sdp: sdpAnswer!, completionHandler: completionHandler);
                return;
            }
            completionHandler(.failure(error));
        });
    }
    
    private func setLocalDescription(peerConnection: RTCPeerConnection, sdp localSDP: RTCSessionDescription, completionHandler: @escaping (Result<SDP,Error>)->Void) {
        print("setting local description:", localSDP.sdp);
        peerConnection.setLocalDescription(localSDP, completionHandler: { err in
            guard let error = err else {
                guard let (sdp, _) = SDP.parse(sdpString: localSDP.sdp, creator: .responder) else {
                    completionHandler(.failure(ErrorCondition.not_acceptable));
                    return;
                }
                self.localSessionDescription = sdp;
                completionHandler(.success(sdp));
                return;
            }
            completionHandler(.failure(error));
        });
    }
    
    func changeState(_ state: State) {
        self.state = state;
        self.delegate?.callStateChanged(self);
    }

    func muted(value: Bool) {
        self.localAudioTrack?.isEnabled = !value;
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

}

protocol CallDelegate: class {
    
    func callDidStart(_ sender: Call);
    func callDidEnd(_ sender: Call);
    
    func callStateChanged(_ sender: Call);
    
    func call(_ sender: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack);
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream stream: String, fromReceiver: String);

    func call(_ sender: Call, goneRemoteVideoTrack remoteTrack: RTCVideoTrack, fromReceiver: String);
    
}

extension CallManager: PKPushRegistryDelegate {
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let tokenString = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined();
        print("PKPush TOKEN:", tokenString)
        PushEventHandler.instance.pushkitDeviceId = tokenString;
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        // need to redesign that.. it is impossible to cancel a call via pushkit..
        if let account = BareJID(payload.dictionaryPayload["account"] as? String) {
            print("voip push for account:", account);
            if let encryped = payload.dictionaryPayload["encrypted"] as? String, let ivStr = payload.dictionaryPayload["iv"] as? String {
                if let key = NotificationEncryptionKeys.key(for: account), let data = Data(base64Encoded: encryped), let iv = Data(base64Encoded: ivStr) {
                    print("got encrypted voip push with known key");
                    let cipher = Cipher.AES_GCM();
                    var decoded = Data();
                    if cipher.decrypt(iv: iv, key: key, encoded: data, auth: nil, output: &decoded) {
                        print("got decrypted voip data:", String(data: decoded, encoding: .utf8) as Any);
                        if let payload = try? JSONDecoder().decode(VoIPPayload.self, from: decoded) {
                            print("decoded voip payload successfully!");
                            if let sender = payload.sender, let client = XmppService.instance.getClient(for: account) {
                                // we require `media` to be present (even empty) in incoming push for jingle session initiation
                                if let media = payload.media {
                                    let session = JingleManager.instance.open(for: client, with: sender, sid: payload.sid, role: .responder, initiationType: .message);
                                    let call = Call(account: account, with: sender.bareJid, sid: payload.sid, direction: .incoming, media: media);
                                    self.reportIncomingCall(call, completionHandler: { result in
                                        switch result {
                                        case .success(_):
                                            break;
                                        case .failure(_):
                                            session.decline();
                                        }
                                        completion();
                                    });
                                } else {
                                    self.endCall(on: account, with: sender.bareJid, sid: payload.sid, completionHandler: {
                                        print("ended call");
                                    })
                                }
                                return;
                            }
                        }
                    }
                }
            }
        }
        
        let uuid = UUID();
        let update = CXCallUpdate();
        update.remoteHandle = CXHandle(type: .generic, value: "Unknown");
        provider.reportNewIncomingCall(with: uuid, update: update, completion: { error in
            if error == nil {
                self.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded);
            }
            completion();
        })
    }
            
            
    class VoIPPayload: Decodable {
        public var sid: String;
        public var sender: JID?;
        public var media: [Call.Media]?;
        
        required public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self);
            sid = try container.decode(String.self, forKey: .sid)
            sender = try container.decodeIfPresent(JID.self, forKey: .sender);
            let media = try container.decodeIfPresent([String].self, forKey: .media);
            self.media = media?.map({ Call.Media.init(rawValue: $0)! });
            // -- and so on...
        }
        
        public enum CodingKeys: String, CodingKey {
            case sid
            case sender
            case media
        }
    }
}

extension Call: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("signaling state:", stateChanged.rawValue);
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
        
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("negotiation required");
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .disconnected:
            break;
            //self.reset();
        case .connected:
            DispatchQueue.main.async {
                self.changeState(.connected);
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
        guard let session = self.session else {
            return;
        }
        for candidate in localCandidates {
            self.sendLocalCandidate(candidate, session: session);
        }
        self.localCandidates = [];
    }
        
    private func sendLocalCandidate(_ candidate: RTCIceCandidate, session: JingleManager.Session) {
        guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp) else {
            return;
        }
        guard let mid = candidate.sdpMid else {
            return;
        }
        guard let sdp = self.localSessionDescription else {
            return;
        }
        
        guard let content = sdp.contents.first(where: { c -> Bool in
            return c.name == mid;
        }), let transport = content.transports.first(where: {t -> Bool in
            return (t as? Jingle.Transport.ICEUDPTransport) != nil;
        }) as? Jingle.Transport.ICEUDPTransport else {
            return;
        }
        
        _ = session.transportInfo(contentName: mid, creator: session.role, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]));
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
            
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        print("added receiver:", rtpReceiver.receiverId)
        if let track = rtpReceiver.track as? RTCVideoTrack, let stream = mediaStreams.first {
            let mid = peerConnection.transceivers.first(where: { $0.receiver.receiverId == rtpReceiver.receiverId })?.mid;
            print("added video track:", track, peerConnection.transceivers.map({ "[\($0.mid) - stopped: \($0.isStopped), \($0.receiver.receiverId), \($0.direction.rawValue)]" }).joined(separator: ", "));
            self.delegate?.call(self, didReceiveRemoteVideoTrack: track, forStream: mid ?? stream.streamId, fromReceiver: rtpReceiver.receiverId);
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        print("removed receiver:", rtpReceiver.receiverId)
        if let track = rtpReceiver.track as? RTCVideoTrack {
            print("removed video track:", track);
            self.delegate?.call(self, goneRemoteVideoTrack: track, fromReceiver: rtpReceiver.receiverId);
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if transceiver.direction == .recvOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                print("got video transceiver");
//                guard let track = transceiver.receiver.track as? RTCVideoTrack else {
//                    return;
//                }
//                self.delegate?.call(self, didReceiveRemoteVideoTrack: track)
            }
        }
        if transceiver.direction == .sendOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                guard let track = transceiver.sender.track as? RTCVideoTrack else {
                    return;
                }
                self.delegate?.call(self, didReceiveLocalVideoTrack: track)
            }
        }
    }
}

extension Call {
    
    func sessionTerminated() {
        DispatchQueue.main.async {
            self.reset();
        }
    }
    
    func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
        guard let peerConnection = self.currentConnection else {
                return;
            }
            peerConnection.add(candidate);
        }
    }
    
    
}
