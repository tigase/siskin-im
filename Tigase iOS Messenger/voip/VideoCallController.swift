//
// VideoCallController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import UIKit
import WebRTC
import TigaseSwift
import UserNotifications

public class VideoCallController: UIViewController {

    #if targetEnvironment(simulator)
    #else
    static func canAccept(session: JingleManager.Session, sdpOffer: SDP) -> Bool {
        guard !sdpOffer.contents.filter({ (content) -> Bool in
            return (content.description?.media == "audio") || (content.description?.media == "video");
        }).isEmpty else {
            return false;
        }
        return true;
    }
    
    static func accept(session: JingleManager.Session, sdpOffer: SDP) -> Bool {
        guard canAccept(session: session, sdpOffer: sdpOffer) else {
            return false;
        }

        let rosterModule: RosterModule? = session.client?.modulesManager.getModule(RosterModule.ID);
        let name = rosterModule?.rosterStore.get(for: session.jid.withoutResource)?.name ?? session.jid.bareJid.stringValue;
        let content = UNMutableNotificationContent();
        content.body = "Incoming call from \(name)";
        content.categoryIdentifier = "CALL";
        if #available(iOS 12.0, *) {
            content.sound = UNNotificationSound.defaultCritical
        } else {
            content.sound = UNNotificationSound.default;
        };
        content.userInfo = ["account": session.account.stringValue, "sender": session.jid.stringValue, "sid": session.sid, "sdpOffer": sdpOffer.toString(), "senderName": name];
        content.threadIdentifier = "account=" + session.account.stringValue + "|sender=" + session.jid.bareJid.stringValue;
        let request = UNNotificationRequest(identifier: session.sid, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { (error) in
            if error != nil {
                print("failed to add incoming call notification", error!);
                _ = session.terminate()
            }
        }
        
        return true;
    }

    static func accept(session: JingleManager.Session, sdpOffer: String, withAudio: Bool, withVideo: Bool, sender: UIViewController) {
        let controller = UIStoryboard(name: "VoIP", bundle: nil).instantiateViewController(withIdentifier: "VideoCallController") as! VideoCallController;
        sender.present(controller, animated: true, completion: {
            controller.accept(session: session, sdpOffer: sdpOffer, withAudio: withAudio, withVideo: withVideo);
        })
    }
    
    static func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool, sender: UIViewController) {
        DispatchQueue.main.async {
            var start = Date();
            let controller = UIStoryboard(name: "VoIP", bundle: nil).instantiateViewController(withIdentifier: "VideoCallController") as! VideoCallController;
            print("created controller in:", Date().timeIntervalSince(start));
            start = Date();
            sender.present(controller, animated: true, completion: {
                print("presented controller in:", Date().timeIntervalSince(start));
                controller.call(jid: jid, from: account, withAudio: withAudio, withVideo: withVideo);
            })
        }
    }
    
    static let peerConnectionFactory = { ()->RTCPeerConnectionFactory in
        RTCPeerConnectionFactory.initialize();
        let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory());
        return factory;
    }();

    fileprivate let hasMetal = MTLCreateSystemDefaultDevice() != nil;
    
    @IBOutlet var titleLabel: UILabel!;
    
    @IBOutlet var remoteVideoView: RTCMTLVideoView!;
    @IBOutlet var localVideoView: CameraPreviewView!;
    
    fileprivate var contactName: String = "Unknown" {
        didSet {
            self.updateTitleLabel();
        }
    }
    @IBOutlet fileprivate var avatar: AvatarView!;
    @IBOutlet fileprivate var avatarWidthConstraint: NSLayoutConstraint!;
    @IBOutlet fileprivate var avatarHeightConstraint: NSLayoutConstraint!;
    
    fileprivate var localVideoCapturer: RTCCameraVideoCapturer?;
    fileprivate var localVideoSource: RTCVideoSource?;
    fileprivate var localVideoTrack: RTCVideoTrack?;
    fileprivate var localAudioTrack: RTCAudioTrack?;
    fileprivate var localCameraPosition: AVCaptureDevice.Position = .front;
    
    fileprivate var remoteVideoTrack: RTCVideoTrack? {
        willSet {
            if remoteVideoTrack != nil && remoteVideoView != nil && hasMetal {
                remoteVideoTrack!.remove(remoteVideoView);
                avatar.isHidden = false;
            }
        }
        didSet {
            if remoteVideoTrack != nil && remoteVideoView != nil && hasMetal {
                remoteVideoTrack!.add(remoteVideoView);
                avatar.isHidden = true;
            }
        }
    }
    
    var session: JingleManager.Session? {
        didSet {
            if let conn = session?.peerConnection {
                if conn.configuration.sdpSemantics == .unifiedPlan {
                    if remoteVideoView != nil {
                        conn.transceivers.forEach { (trans) in
                            if trans.mediaType == .video && (trans.direction == .sendRecv || trans.direction == .recvOnly) {
                                guard let track = trans.receiver.track as? RTCVideoTrack else {
                                    return;
                                }
                                self.didAdd(remoteVideoTrack: track);
                            }
                        }
                    }
                    if localVideoView != nil {
                        conn.transceivers.forEach { (trans) in
                            if trans.mediaType == .video && (trans.direction == .sendRecv || trans.direction == .sendOnly) {
                                guard let track = trans.sender.track as? RTCVideoTrack else {
                                    return;
                                }
                                self.didAdd(localVideoTrack: track);
                            }
                        }
                    }
                    self.state = self.session?.state ?? .disconnected;
                }
            }
        }
    }
    
    var state: JingleManager.Session.State = .created {
        didSet {
            if state == .connected {
                DispatchQueue.main.async {
                    self.avatar.isHidden = (self.remoteVideoTrack?.isEnabled ?? false) && ((self.remoteVideoTrack?.source.state ?? .ended) != .ended);
                }
            }
            print("jingle state changed:", state)
            DispatchQueue.main.async {
                self.updateTitleLabel();
            }
        }
    }
    
    fileprivate var xmppService: XmppService!;
    fileprivate var sessionsInProgress: [JingleManager.Session] = [];

    public override func viewDidLoad() {
        RTCSetMinDebugLogLevel(RTCLoggingSeverity.sensitive);
        xmppService = (UIApplication.shared.delegate as? AppDelegate)?.xmppService;
        super.viewDidLoad();
        let mtkview = self.view.subviews.last!;
        self.view.sendSubviewToBack(mtkview);
//        remoteVideoView.delegate = self;
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.orientationChanged();
    }

    public override func viewWillDisappear(_ animated: Bool) {
        remoteVideoTrack = nil;
        localVideoView.captureSession = nil;
        localVideoCapturer?.stopCapture();
        localVideoCapturer = nil;
        super.viewWillDisappear(animated);
        
        if let session = self.session {
            self.session = nil;
            session.delegate = nil;
            _  = session.terminate();
        }
        self.sessionsInProgress.forEach { (session) in
            session.delegate = nil;
            _ = session.terminate();
        }
    }
    
    
    @objc func orientationChanged() {
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown:
            self.avatarHeightConstraint.isActive = false;
            self.avatarWidthConstraint.isActive = true;
        default:
            self.avatarHeightConstraint.isActive = true;
            self.avatarWidthConstraint.isActive = false;
        }
    }
    
    var wrapper: Wrapper?;
    
    func initializeLocalTracks(requiredMediaTypes: [AVMediaType], completionHandler: @escaping ()->Void) {
        var done: [AVMediaType] = [];
        let finisher = { (type: AVMediaType) in
            DispatchQueue.main.async {
                done.append(type);
                if requiredMediaTypes.filter({ type -> Bool in
                    return done.contains(type);
                }).count == requiredMediaTypes.count {
                    if requiredMediaTypes.contains(.audio) && self.localAudioTrack == nil {
                        self.showAlert(title: "Permission required", message: "To be able to use microphone you need to allow that in the privacy settings", completionHandler: {
                            self.dismiss();
                        })
                    } else if requiredMediaTypes.contains(.video) && self.localVideoTrack == nil {
                        self.showAlert(title: "Permission required", message: "To be able to use camera you need to allow that in the privacy settings", completionHandler: {
                            self.dismiss();
                        })
                    } else {
                        completionHandler();
                    }
                }
            }
        };
        if requiredMediaTypes.contains(.video) {
            AVCaptureDevice.requestAccess(for: .video) { (granted) in
                DispatchQueue.main.async {
                    if granted {
                        self.localVideoSource = VideoCallController.peerConnectionFactory.videoSource();
                        self.wrapper = Wrapper(delegate: self.localVideoSource!);
                        self.localVideoCapturer = RTCCameraVideoCapturer(delegate: self.wrapper!);
                        self.localVideoTrack = VideoCallController.peerConnectionFactory.videoTrack(with: self.localVideoSource!, trackId: "video-" + UUID().uuidString);
                        self.localVideoView.isHidden = false;
                        self.localVideoView.captureSession = self.localVideoCapturer!.captureSession;
                        
                        self.startVideoCapture(videoCapturer: self.localVideoCapturer!) {
                            print("video capturer started!");
                            finisher(.video);
                        }
                    } else {
                        self.localVideoView.isHidden = true;
                        finisher(.video);
                    }
                }
            }
        }
        if requiredMediaTypes.contains(.audio) {
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: { (granted) in
                DispatchQueue.main.async {
                    if granted {
                        self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
                    }
                    finisher(.audio);
                }
            })
        }
        if requiredMediaTypes.isEmpty {
            completionHandler();
        }
    }
    
    func showAlert(title: String, message: String, completionHandler: @escaping ()->Void) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
                self.dismiss();
            }));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    @IBAction func switchCamera(_ sender: UIButton) {
        if localCameraPosition == .front {
            localCameraPosition = .back;
        } else {
            localCameraPosition = .front;
        }
        if let videoCapturer = self.localVideoCapturer {
            startVideoCapture(videoCapturer: videoCapturer) {
                print("camera switched!");
            }
        }
    }
    
    fileprivate func setAudioEnabled(value: Bool) {
        guard let audioTracks = self.session?.peerConnection?.senders.compactMap({ (sender) -> RTCAudioTrack? in
            return sender.track as? RTCAudioTrack;
        }) else {
            return;
        }
        audioTracks.forEach { (track) in
            print("audio is enbled:", track, track.isEnabled);
            track.isEnabled = value;
        }
    }
    
    fileprivate func setVideoEnabled(value: Bool) {
        guard let videoTracks = self.session?.peerConnection?.senders.compactMap({ (sender) -> RTCVideoTrack? in
            return sender.track as? RTCVideoTrack;
        }) else {
            return;
        }
        videoTracks.forEach { (track) in
            print("video is enbled:", track, track.isEnabled);
            track.isEnabled = value;
        }
    }
    
    fileprivate var muted: Bool = false;
    
    @IBAction func mute(_ sender: UIButton) {
        self.muted = !self.muted;
        sender.backgroundColor = self.muted ? UIColor.red : UIColor.white;
        sender.tintColor = self.muted ? UIColor.white : UIColor.black;
        setAudioEnabled(value: !muted);
        setVideoEnabled(value: !muted);
    }
    
    @IBAction func disconnectClicked(_ sender: UIButton) {
        dismiss();
    }
    
    func dismiss() {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: nil);
        }
    }
    
    func accept(session: JingleManager.Session, sdpOffer sdpOfferString: String, withAudio: Bool, withVideo: Bool) {
        session.initiated();
        session.delegate = self;
        let client = session.client;
        let rosterModule: RosterModule? = client?.modulesManager.getModule(RosterModule.ID);
        
        self.contactName = rosterModule?.rosterStore.get(for: session.jid.withoutResource)?.name ?? session.jid.bareJid.stringValue;
        self.avatar.updateAvatar(manager: xmppService.avatarManager, for: session.account, with: session.jid.bareJid, name: self.contactName, orDefault: xmppService.avatarManager.defaultAvatar);
        var requiredMediaTypes: [AVMediaType] = [];
        if (withAudio) {
            requiredMediaTypes.append(.audio);
        }
        if (withVideo) {
            requiredMediaTypes.append(.video);
        }
        
        self.session = session;
        self.initializeLocalTracks(requiredMediaTypes: requiredMediaTypes) {
            session.peerConnection = self.initiatePeerConnection(for: session);
            let sessDesc = RTCSessionDescription(type: .offer, sdp: sdpOfferString);
            self.initializeMedia(for: session, audio: withAudio, video: withVideo) {
                session.peerConnection?.delegate = session;
                print("setting remote description:", sdpOfferString);
                self.setRemoteSessionDescription(sessDesc) {
                    DispatchQueue.main.async {
                        if (session.peerConnection?.configuration.sdpSemantics ?? RTCSdpSemantics.planB) == RTCSdpSemantics.unifiedPlan {
                            session.peerConnection?.transceivers.forEach({ transceiver in
                                if !withAudio && transceiver.mediaType == .audio {
                                    transceiver.stop();
                                }
                                if !withVideo && transceiver.mediaType == .video {
                                    transceiver.stop();
                                }
                            });
                        }
                        
                        session.peerConnection?.answer(for: self.defaultCallConstraints, completionHandler: { (sdpAnswer, error) in
                            guard error == nil else {
                                _ = session.decline();
                                
                                self.showAlert(title: "Call failed!", message: "Negotiation of the call failed", completionHandler: {
                                    self.dismiss();
                                })
                                
                                return;
                            }
                            print("generated local description:", sdpAnswer!.sdp, sdpAnswer!.type);
                            self.setLocalSessionDescription(sdpAnswer!, for: session, onSuccess: {
                                print("set local description:", session.peerConnection?.localDescription?.sdp);
                                
                                let sdp = SDP(from: sdpAnswer!.sdp, creator: session.role);
                                _  = session.accept(contents: sdp!.contents, bundle: sdp!.bundle);
                            })
                        })
                    }

                }
            }
        }
    }
    
    func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool) {
        let client = xmppService.getClient(forJid: account);
        let presenceModule: PresenceModule? = client?.modulesManager.getModule(PresenceModule.ID);
        let rosterModule: RosterModule? = client?.modulesManager.getModule(RosterModule.ID);
        
        self.contactName = rosterModule?.rosterStore.get(for: JID(jid))?.name ?? jid.stringValue;
        self.avatar.updateAvatar(manager: xmppService.avatarManager, for: account, with: jid, name: self.contactName, orDefault: xmppService.avatarManager.defaultAvatar);
        
        guard let presences = presenceModule?.presenceStore.getPresences(for: jid)?.keys, !presences.isEmpty else {
            self.showAlert(title: "Call failed", message: "It was not possible to establish connection. Recipient is unavailable.") {
                self.dismiss();
            };
            return;
        }
        
        var requiredMediaTypes: [AVMediaType] = [];
        if (withAudio) {
            requiredMediaTypes.append(.audio);
        }
        if (withVideo) {
            requiredMediaTypes.append(.video);
        }
        
        let start = Date();
        self.initializeLocalTracks(requiredMediaTypes: requiredMediaTypes) {
            print("intialized local tracks in:", Date().timeIntervalSince(start));
            var waitingFor: Int = presences.count;
            let finisher = { [weak self] in
                guard let that = self else {
                    return;
                }
                
                DispatchQueue.main.async {
                    waitingFor = waitingFor - 1;
                    if waitingFor == 0 && that.sessionsInProgress.isEmpty {
                        that.showAlert(title: "Call failed", message: "It was not possible to establish the connection.") {
                            that.dismiss();
                        }
                    }
                }
            }
            
            presences.forEach { (resource) in
                let session = JingleManager.instance.open(for: account, with: JID(jid, resource: resource), sid: nil, role: .initiator);
                
                session.delegate = self;
                
                print("creating peer connection for:", session.jid);
                session.peerConnection = self.initiatePeerConnection(for: session);
                self.initializeMedia(for: session, audio: withAudio, video: withVideo) {
                    session.peerConnection?.offer(for: self.defaultCallConstraints, completionHandler: { (sdp, error) in
                        if sdp != nil && error == nil {
                            print("setting local description:", sdp!.sdp);
                            let tmp = RTCSessionDescription(type: sdp!.type, sdp: sdp!.sdp.replacingOccurrences(of: "a=mid:0", with: "a=mid:m0").replacingOccurrences(of: "a=group:BUNDLE 0", with: "a=group:BUNDLE m0"));
                            self.setLocalSessionDescription(tmp, for: session, onError: finisher, onSuccess: {
                                let sdpOffer = SDP(from: tmp.sdp, creator: .initiator)!;
                                
                                if session.initiate(sid: sdpOffer.sid, contents: sdpOffer.contents, bundle: sdpOffer.bundle) {
                                    DispatchQueue.main.async {
                                        self.sessionsInProgress.append(session);
                                        session.delegate = self;
                                    }
                                } else {
                                    _ = session.terminate();
                                }
                                
                                finisher();
                            })
                        } else {
                            finisher();
                        }
                    });
                }
            }
        }
    }
    
    fileprivate func updateTitleLabel() {
        switch self.state {
        case .created:
            self.titleLabel.text = "Calling \(contactName)...";
        case .disconnected:
            self.titleLabel.text = "Disconnected from \(contactName)";
        case .negotiating:
            self.titleLabel.text = "Connecting \(contactName)...";
        case .connecting:
            self.titleLabel.text = "Connecting \(contactName)...";
        case .connected:
            self.titleLabel.text = "Call with \(contactName)...";
        }
    }
    
    fileprivate var defaultCallConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil);
    
    func initiatePeerConnection(for session: JingleManager.Session) -> RTCPeerConnection {
        let configuration = RTCConfiguration();
        configuration.sdpSemantics = .unifiedPlan;
        configuration.iceServers = [ RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302","stun:stun1.l.google.com:19302","stun:stun2.l.google.com:19302","stun:stun3.l.google.com:19302","stun:stun4.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stunserver.org:3478"]) ];
        configuration.bundlePolicy = .maxCompat;
        configuration.rtcpMuxPolicy = .require;
        configuration.iceCandidatePoolSize = 3;
        
        return JingleManager.instance.connectionFactory.peerConnection(with: configuration, constraints: self.defaultCallConstraints, delegate: session);
    }
    
    // this may be called multiple times, needs to handle that with video capture!!!
    func initializeMedia(for session: JingleManager.Session, audio: Bool, video: Bool, completionHandler: @escaping ()->Void) {
        //        DispatchQueue.main.async {
        if (session.peerConnection?.configuration.sdpSemantics ?? RTCSdpSemantics.planB) == RTCSdpSemantics.unifiedPlan {
            // send audio?
            if audio, let localAudioTrack = self.localAudioTrack {
                session.peerConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
            }
            
            // send video?
            if video, let localVideoTrack = self.localVideoTrack {
                session.peerConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
            }
            DispatchQueue.main.async {
                completionHandler();
            }
        } else {
            //                let localStream = JingleManager.instance.createLocalStream(audio: audio, video: video);
            //                session.peerConnection?.add(localStream);
            //                if let videoTrack = localStream.videoTracks.first {
            //                    self.didAdd(localVideoTrack: videoTrack);
            //                }
        }
        //        }
    }

    
    fileprivate func startVideoCapture(videoCapturer: RTCCameraVideoCapturer, completionHandler: @escaping ()->Void) {
        if let device = RTCCameraVideoCapturer.captureDevices().filter({ (device) -> Bool in
            device.position == self.localCameraPosition;
        }).first {
            var bestFormat: AVCaptureDevice.Format? = nil;
            var bestFrameRate: AVFrameRateRange? = nil;
            RTCCameraVideoCapturer.supportedFormats(for: device).forEach { (format) in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
                print("checking format:", size.width, "x", size.height, ", fps:", format.videoSupportedFrameRateRanges.map({ (range) -> Float64 in
                    return range.maxFrameRate;
                }).max() ?? 0, ", type:", CMFormatDescriptionGetMediaSubType(format.formatDescription), "expected:", videoCapturer.preferredOutputPixelFormat());
  
                // size of the H264 video in WebRTC on iOS cannot be bigger than 720x480 as it ignores framerate always using 60fps which makes it impossible using default H264 codec (High 3.1).
                if max(size.width, size.height) > 720 || min(size.width, size.height) > 480 {
                    return;
                }

                let currSize = bestFormat == nil ? nil : CMVideoFormatDescriptionGetDimensions(bestFormat!.formatDescription);
                let currRating = currSize == nil ? nil : (currSize!.width * currSize!.height);
                let rating = size.width * size.height;
                
                format.videoSupportedFrameRateRanges.forEach({ (range) in
                    if (bestFrameRate == nil || bestFrameRate!.maxFrameRate < range.maxFrameRate) {
                        bestFrameRate = range;
                        bestFormat = format;
                    } else if (bestFrameRate != nil && bestFrameRate!.maxFrameRate == range.maxFrameRate && (
                        (currRating! < rating)
                            || (CMFormatDescriptionGetMediaSubType(format.formatDescription)) == videoCapturer.preferredOutputPixelFormat())) {
                        bestFormat = format;
                    }
                });
                
            }
            if bestFormat != nil && bestFrameRate != nil {
                self.localVideoCapturer?.startCapture(with: device, format: bestFormat!, fps: min(Int(bestFrameRate!.maxFrameRate), 30)) { error in
                    //print("got error:", error.localizedDescription);
                    print("video capture started with format:", CMVideoFormatDescriptionGetDimensions(bestFormat!.formatDescription), min(Int(bestFrameRate!.maxFrameRate), 30), CMFormatDescriptionGetMediaSubType(bestFormat!.formatDescription));
                    self.localVideoView.cameraChanged();
                    completionHandler();
                }
                return;
            }
        }
        completionHandler();
    }
    
    func didAdd(remoteVideoTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            if self.remoteVideoTrack != nil && self.remoteVideoTrack! == remoteVideoTrack {
                return;
            }
            self.remoteVideoTrack = remoteVideoTrack;
        }
    }
    
    func didAdd(localVideoTrack: RTCVideoTrack) {
        if self.localVideoTrack != nil && self.localVideoTrack! == localVideoTrack {
            return;
        }
        self.localVideoTrack = localVideoTrack;
    }
    
    func sessionTerminated(session: JingleManager.Session) {
        DispatchQueue.main.async {
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                if self.session == nil && self.sessionsInProgress.isEmpty {
                    self.showAlert(title: "Call rejected!", message: "Call was rejected by the recipient.", completionHandler: {
                        self.dismiss();
                    })
                }
            } else if let sess = self.session {
                if sess.sid == session.sid && sess.jid == session.jid && sess.account == session.account {
                    self.session = nil;
                    if let videoCapturer = self.localVideoCapturer {
                        self.localVideoCapturer = nil;
                        videoCapturer.stopCapture();
                    }
                    if self.state == .created {
                        //self.hideAlert();
                    } else {
                        self.showAlert(title: "Call ended!", message: "Call ended.", completionHandler: {
                            self.dismiss();
                        });
                    }
                }
            }
        }
    }
    
    func sessionAccepted(session: JingleManager.Session, sdpAnswer: SDP) {
        DispatchQueue.main.async {
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                self.session = session;
                self.sessionsInProgress.forEach({ (sess) in
                    _ = sess.terminate();
                })
                
                print("setting remote description:", sdpAnswer.toString());
                let sessDesc = RTCSessionDescription(type: .answer, sdp: sdpAnswer.toString());
                self.setRemoteSessionDescription(sessDesc, onSuccess: {
                    print("remote session description set");
                })
            }
        }
    }


    fileprivate func setLocalSessionDescription(_ sessDesc: RTCSessionDescription, for session: JingleManager.Session, onError: (()->Void)? = nil, onSuccess: @escaping ()->Void) {
        DispatchQueue.main.async {
            session.peerConnection?.setLocalDescription(sessDesc, completionHandler: { (error) in
                guard error == nil else {
                    guard onError == nil else {
                        onError!();
                        return;
                    }
                    
                    _ = session.decline();
                    
                    self.showAlert(title: "Call failed!", message: "Negotiation of the call failed", completionHandler: {
                        self.dismiss();
                    })
                    return;
                }
                
                session.localDescriptionSet();
                
                onSuccess();
            });
        }
    }
    
    fileprivate func setRemoteSessionDescription(_ sessDesc: RTCSessionDescription, onSuccess: @escaping ()->Void) {
        guard let session = self.session else {
            return;
        }
        
        session.peerConnection?.setRemoteDescription(sessDesc, completionHandler: { (error) in
            print("remote description set:", session.peerConnection?.remoteDescription?.sdp);
            guard error == nil else {
                session.decline();
                
                self.showAlert(title: "Call failed!", message: "Negotiation of the call failed", completionHandler: {
                    self.dismiss();
                })
                return;
            }
            
            session.remoteDescriptionSet();
            onSuccess();
        });
    }
    
    class Wrapper: NSObject,  RTCVideoCapturerDelegate {
        
        let delegate: RTCVideoCapturerDelegate;
        
        init(delegate: RTCVideoCapturerDelegate) {
            self.delegate = delegate;
        }
        
        func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
            self.delegate.capturer(capturer, didCapture: frame);
        }
        
    }
    #endif
}
