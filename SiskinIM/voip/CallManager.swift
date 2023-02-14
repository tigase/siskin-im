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
import Martin
import TigaseLogging
import Shared
import Combine
import Intents
import CryptoKit

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
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CallManager")
    
    private let pushRegistry: PKPushRegistry;
    
    private let provider: CXProvider;
    private let callController: CXCallController;
    
    private let queue = DispatchQueue(label: "CallManager");
    private var cancellables: Set<AnyCancellable> = [];
    
    private override init() {
        let config = CXProviderConfiguration();
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
        activeCalls.publisher.map({ !$0.isEmpty }).assign(to: \.onCall, on: XmppService.instance).store(in: &cancellables);
        activeCalls.publisher.map({ !$0.isEmpty }).sink(receiveValue: { callInProgress in
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = callInProgress;
            }
        }).store(in: &cancellables);
        
    }
    
//    private func changeCallState(_ state: Call.State) {
//        currentCall?.state = state;
//        delegate?.callStateChanged(self);
//    }
    
    private class ActiveCalls {

        public var publisher: Published<[CallBase]>.Publisher {
            return $calls;
        }
        @Published
        private var calls: [CallBase] = [];
        private let lock = UnfairLock();
        private var callsByUuid: [UUID: CallBase] = [:];
        
        func reportIncoming(call: CallBase) throws -> CallBase {
            return try lock.with({
                guard self.calls.allSatisfy({ !call.isEqual($0) }) else {
                   throw XMPPError(condition: .conflict, message: "Call already registered!");
                }
                
                if let c = call as? Call {
                    if let meet = self.calls.compactMap({ m -> Meet? in
                        guard m.account == c.account && m.jid == c.jid, let meet = m as? Meet else {
                            return nil;
                        }
                        return meet;
                    }).first {
                        return meet;
                    }
                }
                
                self.calls.append(call);
                return call;
            })
        }
        
        func reportOutgoing(call: CallBase) throws {
            try lock.with({
                guard self.calls.allSatisfy({ !call.isEqual($0) }) else {
                    throw XMPPError(condition: .conflict, message: "Call already registered!");
                }
                self.calls.append(call);
            })
        }
        
        func call(forAccount account: BareJID, jid: BareJID, sid: String) -> CallBase? {
            return lock.with({
                return calls.first(where: { $0.account == account && $0.jid == jid && $0.sid == sid })
            })
        }
        
        func call(forAccount account: BareJID, sid: String) -> CallBase? {
            return lock.with({
                return calls.first(where: { $0.account == account && $0.sid == sid })
            })
        }
        
        func call(forUUID key: UUID) -> CallBase? {
            return lock.with({
                return callsByUuid[key];
            })
        }
        
        func register(call: CallBase) {
            lock.with({
                callsByUuid[call.uuid] = call;
            })
        }
        
        func unregister(call: CallBase) {
            lock.with({
                if let idx = calls.firstIndex(where: { $0 === call }) {
                    calls.remove(at: idx);
                }
                callsByUuid.removeValue(forKey: call.uuid);
            })
        }
        
    }
    
    private let activeCalls = ActiveCalls();
    
    func reportIncomingCall(_ inCall: CallBase) async throws {
        let call = try activeCalls.reportIncoming(call: inCall);
        if let meet = call as? Meet, let c = inCall as? Call {
            self.queue.sync {
                c.ringing();
            }
            meet.setIncomingCall(c);
            return;
        }
        
        if #available(iOS 15.0, *) {
            let sender = INPerson(personHandle: INPersonHandle(value: call.jid.description, type: .unknown), nameComponents: nil, displayName: call.name, image: AvatarManager.instance.avatar(for: call.jid, on: call.account)?.inImage(), contactIdentifier: nil, customIdentifier: call.jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INStartCallIntent(callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown, destinationType: .unknown, contacts: [sender], callCapability: AVCaptureDevice.authorizationStatus(for: .video) == .authorized && call.media.contains(.video) ? .videoCall : .audioCall)
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .incoming;
            try await interaction.donate();
        }
        
        #if targetEnvironment(simulator)
        try await call.accept(offerMedia: call.media);
        #else
        let update = CXCallUpdate();
        update.remoteHandle = call.remoteHandle;
        update.localizedCallerName = call.name;
        update.hasVideo = AVCaptureDevice.authorizationStatus(for: .video) == .authorized && call.media.contains(.video);
        
        self.logger.debug("reporting incoming call: \(call.uuid)")
        do {
            let _: Void = try await withUnsafeThrowingContinuation({ continuation in
                self.provider.reportNewIncomingCall(with: call.uuid, update: update, completion: { err in
                    guard let error = err else {
                        continuation.resume(returning: Void());
                        return;
                    }
                    continuation.resume(throwing: error);
                })
            })
            activeCalls.register(call: call);
    
            self.queue.sync {
                call.ringing();
            }
        } catch {
            self.callEnded(call);
    
            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: { _ in });
                if call.media.contains(.video) {
                    AVCaptureDevice.requestAccess(for: .video, completionHandler: { _ in });
                }
                throw ErrorCondition.not_authorized;
            }
        }
        #endif
    }
    
    func reportOutgoingCall(_ call: CallBase) async throws {
        try activeCalls.reportOutgoing(call: call);
        
        if #available(iOS 15.0, *) {
            let recipient = INPerson(personHandle: INPersonHandle(value: call.jid.description, type: .unknown), nameComponents: nil, displayName: call.name, image: AvatarManager.instance.avatar(for: call.jid, on: call.account)?.inImage(), contactIdentifier: nil, customIdentifier: call.jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INStartCallIntent(callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown, destinationType: .unknown, contacts: [recipient], callCapability: AVCaptureDevice.authorizationStatus(for: .video) == .authorized && call.media.contains(.video) ? .videoCall : .audioCall)
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .incoming;
            try await interaction.donate();
        }
        
        let startCallAction = CXStartCallAction(call: call.uuid, handle: call.remoteHandle);
        startCallAction.isVideo = call.media.contains(.video);
        startCallAction.contactIdentifier = call.name;
        let transaction = CXTransaction(action: startCallAction);
        self.logger.debug("reporting outgoing call: \(call.uuid)")
        do {
            try await self.callController.request(transaction);
            activeCalls.register(call: call);
            call.ringing();
        } catch {
            self.callEnded(call);
            throw error;
        }
    }
    
    func providerDidReset(_ provider: CXProvider) {
        self.logger.debug("provider did reset!");
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        self.logger.debug("starting call: \(action.uuid)")

        guard let call = activeCalls.call(forUUID: action.callUUID) else {
            action.fail();
            return;
        }
        
        Task {
            do {
                try await call.start();
                action.fulfill(withDateStarted: Date())
            } catch {
                action.fail()
                self.callEnded(call);
                call.reset();
            }
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        self.logger.debug("answering call: \(action.uuid)")

        guard let call = activeCalls.call(forUUID: action.callUUID) else {
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
                
                Task {
                    do {
                        try await call.accept(offerMedia: call.media);
                        action.fulfill();
                    } catch {
                        self.callEnded(call);
                        action.fail();
                    }
                }
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
        self.logger.debug("ending call: \(action.uuid)")
        guard let call = activeCalls.call(forUUID: action.callUUID) else {
            action.fail();
            return;
        }

        call.end();
        callEnded(call);
        action.fulfill();
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = activeCalls.call(forUUID: action.callUUID) else {
            action.fail();
            return;
        }

        call.mute(value: action.isMuted);
        action.fulfill();
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        self.logger.debug("operation timed out! for: \(action.uuid)");
    }
    
    static func showCallController(completionHandler: (VideoCallController)->Void) {
        var topController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }

        let controller = UIStoryboard(name: "VoIP", bundle: nil).instantiateViewController(withIdentifier: "VideoCallController") as! VideoCallController;
        controller.modalPresentationStyle = .fullScreen;
        topController?.present(controller, animated: true);
//        topController?.show(controller, sender: self);
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
    
    func endCall(_ call: CallBase) {
        guard activeCalls.call(forUUID: call.uuid) != nil else {
            return;
        }
        let endCallAction = CXEndCallAction(call: call.uuid);
        let transaction = CXTransaction(action: endCallAction);
        callController.request(transaction) { error in
            if let error = error {
                #if targetEnvironment(simulator)
                call.reset();
                #else
                fatalError(error.localizedDescription)
                #endif
            }
        }
    }
    
    func endCall(on account: BareJID, with jid: BareJID, sid: String, completionHandler: @escaping ()->Void) {
        logger.debug("endCall(on account) called");
        queue.async {
            guard let call = self.activeCalls.call(forAccount: account, jid: jid, sid: sid) else {
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
    
    func endCall(on account: BareJID, sid: String, completionHandler: (()->Void)? = nil) {
        logger.debug("endCall(on account) called");
        queue.async {
            guard let call = self.activeCalls.call(forAccount: account, sid: sid) else {
                completionHandler?();
                return;
            }
            let endCallAction = CXEndCallAction(call: call.uuid);
            let transaction = CXTransaction(action: endCallAction);
            self.callController.request(transaction) { error in
                call.reset();
                completionHandler?();
            }
        }
    }

    private func callEnded(_ call: CallBase) {
        self.activeCalls.unregister(call: call);
    }
}

protocol CallBase: AnyObject, CustomStringConvertible, Sendable {
    
    var account: BareJID { get }
    var jid: BareJID { get }
    var sid: String { get }
    
    var uuid: UUID { get }
    
    var name: String { get }
    
    var remoteHandle: CXHandle { get }
    
    var media: [Call.Media] { get }
    
    func isEqual(_ call: CallBase) -> Bool;
    
    func reset();
    
    func start() async throws;
    
    func accept(offerMedia: [Call.Media]) async throws;
    
    func ringing();
    
    func end();
    
    func mute(value: Bool);
}

final class Call: NSObject, CallBase, JingleSessionActionDelegate, @unchecked Sendable {
    
    let uuid = UUID();
    
    var name: String {
        return DBRosterStore.instance.item(for: client, jid: JID(jid))?.name ?? jid.description;
    }
    
    var remoteHandle: CXHandle {
        return CXHandle(type: .generic, value: jid.description);
    }
    
    let client: XMPPClient;
    let jid: BareJID;
    let sid: String;
    let direction: Direction;
    let media: [Media]
    
    var account: BareJID {
        return client.userBareJid;
    }
    
    private(set) var state: State = .new;
    
    var webrtcSid: String?;
    
    private(set) var currentConnection: RTCPeerConnection?;
    
    weak var delegate: CallDelegate? {
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

    private let establishingSessions = EstablishingSessions();
    
    private class EstablishingSessions: @unchecked Sendable {
        
        private let lock = UnfairLock();
        private var _completed: Bool = false;
        private var _sessions: [JingleManager.Session] = [];
        
        var isCompleted: Bool {
            lock.lock();
            defer {
                lock.unlock();
            }
            return _completed;
        }
        
        func add(session: JingleManager.Session) throws {
            lock.lock();
            defer {
                lock.unlock();
            }
            guard !_completed else {
                throw XMPPError(condition: .not_acceptable);
            }
            _sessions.append(session);
        }
        
        func sessions() -> [JingleManager.Session] {
            lock.lock();
            defer {
                lock.unlock();
            }
            return _sessions;
        }
        
        func accepted(session: JingleManager.Session) throws -> [JingleManager.Session] {
            lock.lock();
            defer {
                lock.unlock();
            }
            guard !_completed else {
                throw XMPPError(condition: .not_acceptable);
            }
            _completed = true;
            _sessions.removeAll(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid })
            return _sessions;
        }
        
        func rejected(session: JingleManager.Session) {
            lock.lock();
            defer {
                lock.unlock();
            }
            _sessions.removeAll(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid })
            _completed = _completed || _sessions.isEmpty;
        }
        
        func rejectAll() -> [JingleManager.Session] {
            lock.lock();
            defer {
                lock.unlock();
            }
            _completed = true;
            let sessions = _sessions;
            _sessions.removeAll()
            return sessions;
        }
    }
    
    private var localCandidates: [RTCIceCandidate] = [];
    
    private(set) var localVideoSource: RTCVideoSource?;
    private(set) var localVideoTrack: RTCVideoTrack?;
    private(set) var localAudioTrack: RTCAudioTrack?;
    #if targetEnvironment(simulator)
    private(set) var localCapturer: RTCFileVideoCapturer?;
    #else
    private(set) var localCapturer: RTCCameraVideoCapturer?;
    #endif
    private(set) var localCameraDeviceID: String?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override var description: String {
        return "Call[on: \(client.userBareJid), with: \(jid), sid: \(sid), id: \(uuid)]";
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "voip");
    
    init(client: XMPPClient, with jid: BareJID, sid: String, direction: Direction, media: [Media]) {
        self.client = client;
        self.jid = jid;
        self.sid = sid;
        self.media = media;
        self.direction = direction;
    }
    
    func isEqual(_ call: CallBase) -> Bool {
        guard let c = call as? Call else {
            return false;
        }
        return c.account == account && c.jid == jid && c.sid == sid;
    }
    
    func start() async throws {
        await MainActor.run(body: {
            CallManager.showCallController(completionHandler: { controller in
                self.delegate = controller;
            });
        })
        try await initiateOutgoingCall();
    }
    
    func accept(offerMedia: [Media]) async throws {
        await MainActor.run(body: {
            CallManager.showCallController(completionHandler: { controller in
                self.delegate = controller;
            });
        })
        try await self.accept(offerMedia: media);
    }
    
    func end() {
        if self.state == .new || self.state == .ringing {
            self.reject();
        } else {
            self.reset();
        }
    }
    
    func mute(value: Bool) {
        self.localAudioTrack?.isEnabled = !value;
        self.localVideoTrack?.isEnabled = !value;
        let infos: [Jingle.SessionInfo] = self.localSessionDescription?.contents.filter({ $0.description?.media == "audio" || $0.description?.media == "video" }).map({ $0.name }).map({ value ? .mute(contentName: $0) : .unmute(contentName: $0) }) ?? [];
        if !infos.isEmpty {
            Task {
                try await session?.sessionInfo(infos);
            }
        }
    }
    
    func ringing() {
        if direction == .incoming {
            session = JingleManager.instance.session(forCall: self);
        }
        webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        changeState(.ringing);
    }
    
    func reset() {
         DispatchQueue.main.async {
             self.currentConnection?.close();
             self.currentConnection = nil;
             if self.localCapturer != nil {
                #if targetEnvironment(simulator)
                self.localCapturer?.stopCapture();
                #else
                self.logger.debug("\(self), stopping local capturer: \(self.localCapturer)");
                self.localCapturer?.stopCapture(completionHandler: {
                    self.localCapturer = nil;
                })
                #endif
             }
             self.localVideoTrack = nil;
             self.localAudioTrack = nil;
             self.localVideoSource = nil;
             self.delegate?.callDidEnd(self);
             Task {
                 _ = try await self.session?.terminate();
             }
             self.session = nil;
             self.delegate = nil;
             
             for session in self.establishingSessions.rejectAll() {
                 Task {
                     try await session.terminate();

                 }
             }
             self.state = .ended;
         }
     }
    
    enum Media: String, Sendable {
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

    enum Direction: Sendable {
        case incoming
        case outgoing
    }
    
    enum State: Sendable {
        case new
        case ringing
        case connecting
        case connected
        case ended
    }

    private func findJidsWithJingle() -> [JID] {
        return PresenceStore.instance.presences(for: jid, context: client).compactMap({
            guard let jid = $0.from, let node = $0.capsNode, DBCapabilitiesCache.instance.areSupported(features: [JingleModule.XMLNS, Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:rtp:audio"], for: node) else {
                return nil;
            }
            return jid;
        });
    }
    
    private func findJidsWithMessageInitiation() -> [JID] {
        return PresenceStore.instance.presences(for: jid, context: client).compactMap({
            guard let jid = $0.from, let node = $0.capsNode, DBCapabilitiesCache.instance.isSupported(feature: JingleModule.MESSAGE_INITIATION_XMLNS, for: node) else {
                return nil;
            }
            return jid;
        });
    }
    
    private func checkAllHaveJMI(jids: [JID]) -> Bool {
        for jid in jids {
            if let node = PresenceStore.instance.presence(for: jid, context: client)?.capsNode {
                if !DBCapabilitiesCache.instance.isSupported(feature: JingleModule.MESSAGE_INITIATION_XMLNS, for: node) {
                    return false;
                }
            }
        }
        return true;
    }

    func initiateOutgoingCall(with callee: JID? = nil) async throws {
        guard let client = XmppService.instance.getClient(for: account) else {
            throw XMPPError(condition: .item_not_found);
        }
        let withJingle: [JID] = callee != nil ? [callee!] : findJidsWithJingle();
        let allHaveJMI = callee == nil && checkAllHaveJMI(jids: withJingle);
                
        self.changeState(.ringing);
        do {
            try initiateWebRTC(iceServers: await discoverIceServers(), offerMedia: media);
        } catch {
            reset();
            throw error;
        }
        
        Task {
            if allHaveJMI {
                let session = JingleManager.instance.open(for: client, with: JID(self.jid), sid: self.sid, role: .initiator, initiationType: .message);
                self.session = session;
                do {
                    try await session.initiate(descriptions: self.media.map({ Jingle.MessageInitiationAction.Description(xmlns: "urn:xmpp:jingle:apps:rtp:1", media: $0.rawValue) }));
                } catch {
                    self.reset();
                }
            } else {
                // we need to establish multiple 1-1 sessions...
                guard let peerConnection = self.currentConnection else {
                    return;
                }
                do {
                    let sdp = try await generateOfferAndSet(peerConnection: peerConnection, creatorProvider: { _ in Jingle.Content.Creator.initiator }, localRole: .initiator);
                    let sessions = withJingle.compactMap({ jid -> JingleManager.Session? in
                        let session = JingleManager.instance.open(for: client, with: jid, sid: self.sid, role: .initiator, initiationType: .iq);
                        session.$state.removeDuplicates().sink(receiveValue: { state in
                            switch state {
                            case .accepted:
                                Task {
                                    guard self.session == nil else {
                                        try await session.terminate();
                                        return;
                                    }
                                    
                                    do {
                                        for sess in try self.establishingSessions.accepted(session: session) {
                                            Task {
                                                try await sess.terminate();
                                            }
                                        }
                                        
                                        self.session = session;
                                        self.state = .connecting;
                                        self.connectRemoteSDPPublishers(session: session);
                                        self.sendLocalCandidates();
                                    } catch {
                                        try await session.terminate();
                                    }
                                }
                            case .terminated:
                                Task {
                                    self.establishingSessions.rejected(session: session);
                                    if self.establishingSessions.isCompleted && self.session == nil {
                                        self.reset();
                                    }
                                }
                            default:
                                break;
                            }
                        }).store(in: &self.cancellables);
                        do {
                            try self.establishingSessions.add(session: session);
                            return session;
                        } catch {
                            return nil;
                        }
                    })
                    for session in sessions {
                        Task {
                            do {
                                try await session.initiate(contents: sdp.contents, bundle: sdp.bundle);
                            } catch let error as XMPPError {
                                if error.condition == .remote_server_timeout {
                                    self.establishingSessions.rejected(session: session);
                                    if self.establishingSessions.isCompleted && self.session == nil {
                                        self.reset();
                                    }
                                } else {
                                    throw error;
                                }
                            }
                        }
                    }
                } catch {
                    self.reset();
                }
            }
        }
    }
        
    private func acceptedOutgingCall() {
        guard let session = session, session.initiationType == .message, state == .ringing, let peerConnection = self.currentConnection else {
            return;
        }
        changeState(.connecting);
        Task {
            do {
                let sdp = try await generateOfferAndSet(peerConnection: peerConnection, creatorProvider: session.contentCreator(of:), localRole: session.role);
                self.connectRemoteSDPPublishers(session: session);
                try await session.initiate(contents: sdp.contents, bundle: sdp.bundle);
            } catch {
                self.reset();
            }
        }
    }
    
    private func connectRemoteSDPPublishers(session: JingleManager.Session) {
        session.setDelegate(self);
    }
        
    static let VALID_SERVICE_TYPES = ["stun", "stuns", "turn", "turns"];
    
    private func discoverIceServers() async -> [RTCIceServer] {
        if let module: ExternalServiceDiscoveryModule = XmppService.instance.getClient(for: self.account)?.module(.externalServiceDiscovery), module.isAvailable {
            do {
                let services = try await module.discover(from: nil, type: nil);
                return services.compactMap({ $0.rtcIceServer() })
            } catch {}
        }
        return [];
    }
    
    #if targetEnvironment(simulator)
//    var repeatingVideoTimer: Timer?;
    #endif
    
    var audioSession: AudioSesion?;
    
    private func initiateWebRTC(iceServers: [RTCIceServer], offerMedia media: [Media]) throws {
        self.currentConnection = VideoCallController.initiatePeerConnection(iceServers: iceServers, withDelegate: self);
        if self.currentConnection != nil {
            if media.contains(.audio) {
                let avsession = AVAudioSession.sharedInstance()
                try avsession.setCategory(.playAndRecord, mode: media.contains(.video) ? .videoChat : .voiceChat, options: [.allowBluetooth,.allowBluetoothA2DP])
                try avsession.setPreferredIOBufferDuration(0.005)
                //try avsession.setPreferredSampleRate(4_410)

                self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
                if let localAudioTrack = self.localAudioTrack {
                    self.currentConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
                }
            }
            #if targetEnvironment(simulator)
            let hasAvPermission = true;
            #else
            let hasAvPermission = AVCaptureDevice.authorizationStatus(for: .video) == .authorized;
            #endif
            if media.contains(.video) && hasAvPermission {
                let videoSource = VideoCallController.peerConnectionFactory.videoSource();
                self.localVideoSource = videoSource;
                let localVideoTrack = VideoCallController.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video-" + UUID().uuidString);
                self.localVideoTrack = localVideoTrack;
                #if targetEnvironment(simulator)
                let localVideoCapturer = RTCFileVideoCapturer(delegate: videoSource)
                #else
                let localVideoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                #endif
                self.localCapturer = localVideoCapturer;
                
                #if targetEnvironment(simulator)
                localVideoCapturer.startCapturing(fromFileNamed: "foreman.mp4", onError: { error in
                    self.logger.debug("failed to start video capturer: \(error)");
                });
                self.delegate?.call(self, didReceiveLocalVideoTrack: localVideoTrack);
                self.currentConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                #else
                if let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }), let format = RTCCameraVideoCapturer.format(for: device, preferredOutputPixelFormat: localVideoCapturer.preferredOutputPixelFormat()) {
                    self.logger.debug("\(self), starting video capture on: \(device), with: \(format), fps: \(RTCCameraVideoCapturer.fps(for: format))");
                    self.localCameraDeviceID = device.uniqueID;
                    localVideoCapturer.startCapture(with: device, format: format, fps: RTCCameraVideoCapturer.fps(for:  format), completionHandler: { error in
                        self.logger.debug("\(self), video capturer started!");

                    });
                    self.delegate?.call(self, didReceiveLocalVideoTrack: localVideoTrack);
                    self.currentConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                } else {
                    throw XMPPError(condition: .not_authorized);
                }
                #endif
            }
        } else {
           throw XMPPError(condition: .internal_server_error);
        }
    }

    func accept(offerMedia media: [Media]) {
        guard let session = self.session else {
            reset();
            return;
        }
        changeState(.connecting);
        Task {
            do {
                try initiateWebRTC(iceServers: await discoverIceServers(), offerMedia: media);
                guard self.currentConnection != nil else {
                    self.reject();
                    return;
                }
                try await session.accept();
                self.connectRemoteSDPPublishers(session: session);
            } catch {
                self.reject();
            }
        }
    }
    
    func reject() {
        guard let session = self.session else {
            reset();
            return;
        }
        Task {
            try await session.decline();
        }
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
                peerConnection.add(RTCIceCandidate(sdp: candidate.toSDP(), sdpMLineIndex: Int32(idx), sdpMid: contentName), completionHandler: { _ in });
                remoteSessionSemaphore.signal();
            }
            return;
        }
            
        let result = apply(action: action, on: self.remoteSessionDescription);
            
        guard let newSDP = result else {
            remoteSessionSemaphore.signal();
            return;
        }
            
        let prevLocalSDP = self.localSessionDescription;
        Task {
            do {
                if let localSDP = try await setRemoteDescription(newSDP, peerConnection: peerConnection, session: session) {
                    if let prevLocalSDP = prevLocalSDP {
                        let changes = localSDP.diff(from: prevLocalSDP);
                        if let addSDP = changes[.add] {
                            Task {
                                try await session.contentModify(action: .accept, contents: addSDP.contents, bundle: addSDP.bundle);
                            }
                        }
                        if let modifySDP = changes[.modify] {
                            // can we safely ignore this?
                        }
                    } else {
                        Task {
                            try await session.accept(contents: localSDP.contents, bundle: localSDP.bundle)
                        }
                        Task {
                            try await Task.sleep(nanoseconds: 100 * 1000 * 1000);
                            sendLocalCandidates();
                        }
                    }
                }
            } catch {
                self.logger.error("error setting remote description: \(error)");
                self.reset();
            }
        }
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
        case .sessionInfo(let infos):
            for info in infos {
                logger.debug("\(self), received session info: \(String(describing: info))")
            }
            return nil;
        }
    }
    
    private func setRemoteDescription(_ remoteDescription: SDP, peerConnection: RTCPeerConnection, session: JingleSession) async throws -> SDP? {
        logger.debug("\(self), setting remote description: \(remoteDescription.toString(withSid: "", localRole: session.role, direction: .incoming))");
        try await peerConnection.setRemoteDescription(RTCSessionDescription(type: self.direction == .incoming ? .offer : .answer, sdp: remoteDescription.toString(withSid: self.webrtcSid!, localRole: session.role, direction: .incoming)));
        self.remoteSessionDescription = remoteDescription;
        if peerConnection.signalingState == .haveRemoteOffer {
            return try await self.generateAnswerAndSet(peerConnection: peerConnection, creatorProvider: session.contentCreator(of:), localRole: session.role);
        } else {
            return nil;
        }
    }
    
    private func generateOfferAndSet(peerConnection: RTCPeerConnection, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator) async throws -> SDP {
        logger.debug("\(self), generating offer");
        let sdpOffer = try await peerConnection.offer(for: VideoCallController.defaultCallConstraints);
        return try await setLocalDescription(peerConnection: peerConnection, sdp: sdpOffer, creatorProvider: creatorProvider, localRole: localRole);
    }
        
    private func generateAnswerAndSet(peerConnection: RTCPeerConnection, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator) async throws -> SDP {
        logger.debug("\(self), generating answer");
        let sdpAnswer = try await peerConnection.answer(for: VideoCallController.defaultCallConstraints);
        return try await setLocalDescription(peerConnection: peerConnection, sdp: sdpAnswer, creatorProvider: creatorProvider, localRole: localRole);
    }
    
    private func setLocalDescription(peerConnection: RTCPeerConnection, sdp localSDP: RTCSessionDescription, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator) async throws -> SDP {
        logger.debug("\(self), setting local description: \(localSDP.sdp)");
        try await peerConnection.setLocalDescription(localSDP);
        guard let (sdp, _) = SDP.parse(sdpString: localSDP.sdp, creatorProvider: creatorProvider, localRole: localRole) else {
            throw XMPPError(condition: .not_acceptable);
        }
        localSessionDescription = sdp;
        return sdp;
    }
    
    func changeState(_ state: State) {
        self.state = state;
        self.delegate?.callStateChanged(self);
    }
    
    func switchCameraDevice() {
        #if targetEnvironment(simulator)
        #else
        if let localCapturer = self.localCapturer, let deviceID = self.localCameraDeviceID {
            let position = RTCCameraVideoCapturer.captureDevices().first(where: { $0.uniqueID == deviceID })?.position ?? .front;
            if let newCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position != position }), let format = RTCCameraVideoCapturer.format(for: newCamera, preferredOutputPixelFormat: localCapturer.preferredOutputPixelFormat()) {
                self.localCameraDeviceID = newCamera.uniqueID;
                localCapturer.startCapture(with: newCamera, format: format, fps: RTCCameraVideoCapturer.fps(for: format));
            }
        }
        #endif
    }

}

protocol CallDelegate: AnyObject {
    
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
        logger.info("received PKPush token: \(tokenString)");
        PushEventHandler.instance.pushkitDeviceId = tokenString;
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        // need to redesign that.. it is impossible to cancel a call via pushkit..
        if let account = BareJID(payload.dictionaryPayload["account"] as? String) {
            logger.debug("voip push for account: \(account)");
            if let encryped = payload.dictionaryPayload["encrypted"] as? String, let ivStr = payload.dictionaryPayload["iv"] as? String {
                if let key = NotificationEncryptionKeys.key(for: account), let data = Data(base64Encoded: encryped), let iv = Data(base64Encoded: ivStr) {
                    logger.debug("got encrypted voip push with known key");
                    if let decoded = try? AES.GCM.open(.init(nonce: .init(data: iv), ciphertext: data, tag: Data()), using: SymmetricKey(data: key)) {
                        logger.debug("got decrypted voip data: \(String(data: decoded, encoding: .utf8) as Any)");
                        if let payload = try? JSONDecoder().decode(VoIPPayload.self, from: decoded) {
                            logger.debug("decoded voip payload successfully!");
                            if let sender = payload.sender, let client = XmppService.instance.getClient(for: account) {
                                // we require `media` to be present (even empty) in incoming push for jingle session initiation
                                if let media = payload.media {
                                    let session = JingleManager.instance.open(for: client, with: sender, sid: payload.sid, role: .responder, initiationType: .message);
                                    let call = Call(client: client, with: sender.bareJid, sid: payload.sid, direction: .incoming, media: media);
                                    Task {
                                        do {
                                            try await self.reportIncomingCall(call);
                                        } catch {
                                            try? await session.decline();
                                        }
                                        completion();
                                    }
                                } else {
                                    self.endCall(on: account, with: sender.bareJid, sid: payload.sid, completionHandler: {
                                        self.logger.debug("ended call");
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
        self.logger.debug("\(self), signaling state: \(stateChanged.rawValue)");
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
        
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        self.logger.debug("\(self), negotiation required");
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
        JingleManager.instance.queue.async {
            self.localCandidates.append(candidate);
            self.sendLocalCandidates();
        }
    }
        
    private func sendLocalCandidates() {
        guard let session = self.session, !localCandidates.isEmpty else {
            return;
        }
        
        for candidate in localCandidates {
            Task {
                try await sendLocalCandidate(candidate, session: session)
            }
        }
        localCandidates = [];
    }
        
    private func sendLocalCandidate(_ candidate: RTCIceCandidate, session: JingleManager.Session) async throws {
        guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp) else {
            throw XMPPError(condition: .not_acceptable);
        }
        guard let mid = candidate.sdpMid else {
            throw XMPPError(condition: .not_acceptable);
        }
        guard let sdp = self.localSessionDescription else {
            throw XMPPError(condition: .unexpected_request);
        }
        
        guard let content = sdp.contents.first(where: { c -> Bool in
            return c.name == mid;
        }), let transport = content.transports.first(where: {t -> Bool in
            return (t as? Jingle.Transport.ICEUDPTransport) != nil;
        }) as? Jingle.Transport.ICEUDPTransport else {
            throw XMPPError(condition: .not_acceptable);
        }
        
        try await session.transportInfo(contentName: mid, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]));
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
            
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        logger.debug("\(self), added receiver: \(rtpReceiver.receiverId)");
        if let track = rtpReceiver.track as? RTCVideoTrack, let stream = mediaStreams.first {
            let mid = peerConnection.transceivers.first(where: { $0.receiver.receiverId == rtpReceiver.receiverId })?.mid;
            logger.debug("\(self), added video track: \(track), \(peerConnection.transceivers.map({ "[\($0.mid) - stopped: \($0.isStopped), \($0.receiver.receiverId), \($0.direction.rawValue)]" }).joined(separator: ", "))");
            self.delegate?.call(self, didReceiveRemoteVideoTrack: track, forStream: mid ?? stream.streamId, fromReceiver: rtpReceiver.receiverId);
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        logger.debug("\(self), removed receiver: \(rtpReceiver.receiverId)");
        if let track = rtpReceiver.track as? RTCVideoTrack {
            logger.debug("\(self), removed video track: \(track)");
            self.delegate?.call(self, goneRemoteVideoTrack: track, fromReceiver: rtpReceiver.receiverId);
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if transceiver.direction == .recvOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                logger.debug("\(self), got video transceiver");
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
            CallManager.instance?.endCall(self);
        }
    }
    
    func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
        guard let peerConnection = self.currentConnection else {
                return;
            }
            peerConnection.add(candidate, completionHandler: { _ in });
        }
    }
    
    
}
