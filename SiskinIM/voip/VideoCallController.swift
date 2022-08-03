//
// VideoCallController.swift
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

import UIKit
import WebRTC
import Martin
import UserNotifications
import os
//import CallKit

public class VideoCallController: UIViewController, RTCVideoViewDelegate, CallDelegate {
    
    private var call: Call?;
    
    fileprivate var localVideoTrack: RTCVideoTrack? {
        willSet {
            if localVideoTrack != nil && localVideoView != nil {
                localVideoTrack!.remove(localVideoView!);
            }
        }
        didSet {
            if localVideoTrack != nil && localVideoView != nil {
                localVideoTrack!.add(localVideoView!);
            }
        }
    }
    fileprivate var remoteVideoTrack: RTCVideoTrack? {
        willSet {
            if remoteVideoTrack != nil && remoteVideoView != nil {
                remoteVideoTrack!.remove(remoteVideoView);
                self.updateAvatarVisibility();
            }
        }
        didSet {
            if remoteVideoTrack != nil && remoteVideoView != nil {
                remoteVideoTrack!.add(remoteVideoView);
                self.updateAvatarVisibility();
            }
        }
    }
    
    public func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        // lets do not do anything for now...
//        DispatchQueue.main.async {
//            if videoView === self.localVideoView! {
//                self.lo
//            }
//        }
    }
    
    func callDidStart(_ sender: Call) {
        self.call = sender;
        self.audioSession = AudioSesion(preferSpeaker: true)
        self.updateAvatarView();
        self.updateStateLabel();
    }
    
    func callDidEnd(_ sender: Call) {
        self.call = nil;
        self.dismiss(animated: true, completion: nil);
    }
    
    func callStateChanged(_ sender: Call) {
        self.updateStateLabel();
    }
    
    func call(_ sender: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            self.localVideoTrack = localTrack;
        }
    }
    
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream: String, fromReceiver: String) {
        DispatchQueue.main.async {
            self.remoteVideoTrack = remoteTrack;
        }
    }
    
    func call(_ sender: Call, goneRemoteVideoTrack remoteTrack: RTCVideoTrack, fromReceiver: String) {
        
    }
    
//    #if targetEnvironment(simulator)
//    func callDidStart(_ sender: CallManager) {
//    }
//    func callDidEnd(_ sender: CallManager) {
//    }
//    func callManager(_ sender: CallManager, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack) {
//    }
//    func callManager(_ sender: CallManager, didReceiveLocalVideoCapturer localCapturer: RTCCameraVideoCapturer) {
//    }
//    func callStateChanged(_ sender: CallManager) {
//    }
//    #else

        
    static func checkMediaAvailability(forCall call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        var errors: Bool = false;
        let group = DispatchGroup();
        group.enter();
        for media in call.media {
            group.enter();
            self.checkAccesssPermission(media: media, completionHandler: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        break;
                    case .failure(_):
                        errors = true;
                    }
                    group.leave();
                }
            })
        }
        group.leave();
        group.notify(queue: DispatchQueue.main, execute: {
            completionHandler(errors ? .failure(ErrorCondition.forbidden) : .success(Void()));
        })
    }

    static func checkAccesssPermission(media: Call.Media, completionHandler: @escaping(Result<Void,Error>)->Void) {
        switch AVCaptureDevice.authorizationStatus(for: media.avmedia) {
        case .authorized:
            completionHandler(.success(Void()));
        case .denied, .restricted:
            completionHandler(.failure(ErrorCondition.forbidden));
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: media.avmedia, completionHandler: { result in
                completionHandler(result ? .success(Void()) : .failure(ErrorCondition.forbidden));
            })
        default:
            completionHandler(.failure(ErrorCondition.forbidden));
        }
    }
    
    static func call(jid: BareJID, from account: BareJID, media: [Call.Media], sender: UIViewController) {
        call(jid: jid, from: account, media: media, completionHandler: { result in
            switch result {
            case .success(_):
                break;
            case .failure(let err):
                var message = NSLocalizedString("It was not possible to establish call", comment: "error message");
                if let e = err as? ErrorCondition {
                    switch e {
                    case .forbidden:
                        message = NSLocalizedString("It was not possible to access camera or microphone. Please check privacy settings", comment: "error message");
                    default:
                        break;
                    }
                }
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: NSLocalizedString("Call failed", comment: "alert title"), message: message, preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                    sender.present(alert, animated: true, completion: nil);
                }
            }
        });
    }
    
    static func call(jid: BareJID, from account: BareJID, media: [Call.Media], completionHandler: @escaping (Result<Void,Error>)->Void) {
        guard let instance = CallManager.instance else {
            completionHandler(.failure(ErrorCondition.not_allowed))
            return;
        }
        guard let client = XmppService.instance.getClient(for: account) else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        }
        
        let continueCall = {
            // we do not know "internal id" of a session
            let call = Call(client: client, with: jid, sid: UUID().uuidString, direction: .outgoing, media: media);
                
            checkMediaAvailability(forCall: call, completionHandler: { result in
                switch result {
                case .success(_):
                    instance.reportOutgoingCall(call, completionHandler: completionHandler);
                case .failure(let err):
                    completionHandler(.failure(err));
                }

            })
        };
        
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: { result in
            if result {
                if media.contains(.video) {
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: { result in
                        if result {
                            continueCall();
                        } else {
                            completionHandler(.failure(ErrorCondition.not_allowed))
                        }
                    });
                } else {
                    continueCall();
                }
            } else {
                completionHandler(.failure(ErrorCondition.not_allowed))
            }
        });
        
        
    }

    @IBOutlet var titleLabel: UILabel?;
    
    @IBOutlet var remoteVideoView: RTCMTLVideoView!;
    @IBOutlet var localVideoView: RTCMTLVideoView!;
    
    @IBOutlet fileprivate var avatar: AvatarView?;
    @IBOutlet fileprivate var avatarWidthConstraint: NSLayoutConstraint!;
    @IBOutlet fileprivate var avatarHeightConstraint: NSLayoutConstraint!;
        
    private var audioSession: AudioSesion?;
    
    public override func viewDidLoad() {
        super.viewDidLoad();

        localVideoView.layer.cornerRadius = 5;
        
        self.updateStateLabel();
        self.updateAvatarView();
        
        let mtkview = self.view.subviews.last!;
        self.view.sendSubviewToBack(mtkview);
//        remoteVideoView.delegate = self;
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
        
//    var timer: Foundation.Timer?;
    
    public override func viewWillAppear(_ animated: Bool) {
        self.updateAvatarView();
        super.viewWillAppear(animated);
        self.orientationChanged();
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
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
    
    @IBAction func switchCamera(_ sender: UIButton) {
        call?.switchCameraDevice();
    }
    
    @IBAction func selectAudioDevice(_ sender: UIButton) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
        for audioPort in audioSession?.availableAudioPorts() ?? [] {
            let action = UIAlertAction(title: audioPort.label, style: .default, handler: { action in
                self.audioSession?.set(outputMode: audioPort);
            });

            switch audioPort {
            case .automatic:
                break;
            case .builtin:
                action.setValue(AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }), forKey: "checked")
            case .speaker:
                action.setValue(AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }), forKey: "checked")
            case .custom(let port):
                action.setValue(AVAudioSession.sharedInstance().currentRoute.inputs.contains(where: { $0.portType == port.portType }), forKey: "checked");
            }
            
            if let image = audioPort.icon {
                action.setValue(image.scaled(maxWidthOrHeight: 30, isOpaque: false), forKey: "image");
            }
            
            controller.addAction(action)
        }
        
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        
        controller.popoverPresentationController?.sourceView = sender;
        controller.popoverPresentationController?.sourceRect = sender.bounds;
        self.present(controller, animated: true, completion: nil);
    }

    fileprivate var muted: Bool = false;
    
    @IBAction func mute(_ sender: UIButton) {
        self.muted = !self.muted;
        if let instance = CallManager.instance, let call = self.call {
            instance.muteCall(call, value: self.muted);
        }
        sender.backgroundColor = self.muted ? UIColor.red : UIColor.white;
        sender.tintColor = self.muted ? UIColor.white : UIColor.black;
    }
    
    @IBAction func disconnectClicked(_ sender: UIButton) {
        if let instance = CallManager.instance, let call = self.call {
            instance.endCall(call);
        }
        dismiss();
    }
    
    func dismiss() {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: nil);
        }
    }
        
    
    private func updateAvatarVisibility() {
        DispatchQueue.main.async {
            self.avatar?.isHidden = self.remoteVideoTrack != nil && (self.call?.state ?? .new) == .connected;
        }
    }
    
    private func updateAvatarView() {
        if let call = self.call {
            avatar?.set(name: DBRosterStore.instance.item(for: call.account, jid: JID(call.jid))?.name ?? call.jid.stringValue, avatar: AvatarManager.instance.avatar(for: call.jid, on: call.account));
        } else {
            avatar?.set(name: nil, avatar: nil);
        }
    }
    
    fileprivate func updateStateLabel() {
        DispatchQueue.main.async {
            self.updateAvatarVisibility();
            switch self.call?.state ?? .new {
            case .new:
                self.titleLabel?.text = NSLocalizedString("New call", comment: "call state label");
            case .ringing:
                self.titleLabel?.text = NSLocalizedString("Ringing…", comment: "call state label");
            case .connecting:
                self.titleLabel?.text = NSLocalizedString("Connecting…", comment: "call state label");
            case .connected:
                self.titleLabel?.text = nil;
            case .ended:
                self.titleLabel?.text = NSLocalizedString("Call ended", comment: "call state label");
            }
        }
    }
//    #endif
    
    static var peerConnectionFactory: RTCPeerConnectionFactory {
        return JingleManager.instance.connectionFactory;
    }

    static let defaultCallConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil);
    
    static func initiatePeerConnection(iceServers servers: [RTCIceServer], withDelegate delegate: RTCPeerConnectionDelegate) -> RTCPeerConnection? {
        
        let iceServers = (servers.isEmpty && Settings.usePublicStunServers) ? [ RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302","stun:stun1.l.google.com:19302","stun:stun2.l.google.com:19302","stun:stun3.l.google.com:19302","stun:stun4.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stunserver.org:3478"]) ] : servers;
        os_log("using ICE servers: %s", log: .jingle, type: .debug, iceServers.map({ $0.urlStrings.description }).description);

        let configuration = RTCConfiguration();
        configuration.tcpCandidatePolicy = .disabled;
        configuration.sdpSemantics = .unifiedPlan;
        configuration.iceServers = iceServers;
        configuration.bundlePolicy = .maxCompat;
        configuration.rtcpMuxPolicy = .require;
        configuration.iceCandidatePoolSize = 5;
        
        return JingleManager.instance.connectionFactory.peerConnection(with: configuration, constraints: defaultCallConstraints, delegate: delegate);
    }

}
