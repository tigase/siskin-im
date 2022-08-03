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

import UIKit
import WebRTC
import Combine
import Martin
import TigaseLogging

class MeetController: UIViewController, UICollectionViewDataSource, RTCVideoViewDelegate, CallDelegate {
    
    func callDidStart(_ sender: Call) {
        // nothing to do..
    }
    
    func callDidEnd(_ sender: Call) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: NSLocalizedString("Meeting ended", comment: "alert title"), message: NSLocalizedString("Meeting has ended", comment: "alert body"), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                self.endCall(self);
            }));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    func callStateChanged(_ sender: Call) {
        // nothing to do..
    }
    
    func call(_ sender: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            localTrack.add(self.localVideoRenderer);
        }
    }
    
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream mid: String, fromReceiver receiverId: String) {
        DispatchQueue.main.async {
            self.items.append(Item(mid: mid, videoTrack: remoteTrack, receiverId: receiverId));
            self.collectionView.performBatchUpdates({
                self.collectionView.insertItems(at: [IndexPath(item: self.items.count - 1, section: 0)]);
            }, completion: nil);
        }
    }
    
    func call(_ sender: Call, goneRemoteVideoTrack remoteTrack: RTCVideoTrack, fromReceiver receiverId: String) {
        DispatchQueue.main.async {
            if let idx = self.items.firstIndex(where: { $0.receiverId == receiverId }) {
                self.items.remove(at: idx);
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: idx, section: 0)]);
                }, completion: nil);
            }
        }
    }
    
    func call(_ sender: Call, goneLocalVideoTrack localTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            localTrack.remove(self.localVideoRenderer);
        }
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "meet")
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: FlowLayout());
    
    private let collectonViewDelegate = CollectionViewDelegate();
    
    private let buttonsStack = UIStackView(frame: .zero);
    
    private var endCallButton: RoundButton?;
    private var muteButton: RoundButton?;
    private var moreButton: RoundButton?;
    
    #if targetEnvironment(simulator)
    private let localVideoRenderer = RTCEAGLVideoView();
    #else
    private let localVideoRenderer = RTCMTLVideoView();
    #endif
    private var localVideoRendererWidth: NSLayoutConstraint?;
    
    private var cancellables: Set<AnyCancellable> = [];

    @Published
    private var publisherByMid: [String: MeetModule.Publisher] = [:];
    
    private var remove: Bool = true;
    private var items: [Item] = [];
    
    private var audioSession: AudioSesion?;
    
    private var meet: Meet? {
        didSet {
            meet?.$outgoingCall.sink(receiveValue: { [weak self] call in
                guard let that = self else {
                    return;
                }
                call?.delegate = that;
            }).store(in: &cancellables);
            meet?.$incomingCall.sink(receiveValue: { [weak self] call in
                guard let that = self else {
                    return;
                }
                call?.delegate = that;
            }).store(in: &cancellables);
            meet?.$publishers.sink(receiveValue: { [weak self] publishers in
                var dict: [String: MeetModule.Publisher] = [:];
                for publisher in publishers {
                    for stream in publisher.streams {
                        dict[stream] = publisher;
                    }
                }
                self?.publisherByMid = dict;
            }).store(in: &cancellables);
            if meet != nil {
                self.audioSession = AudioSesion(preferSpeaker: true);
            }
        }
    }
    
    private var muted: Bool = false {
        didSet {
            muteButton?.tintColor = muted ? UIColor.red : UIColor.white;
        }
    }
    
    public static func open(meet: Meet) {
        DispatchQueue.main.async {
            var topController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController;
            while (topController?.presentedViewController != nil) {
                topController = topController?.presentedViewController;
            }

            let controller = MeetController();
            controller.meet = meet;
            controller.modalPresentationStyle = .fullScreen;
            controller.modalTransitionStyle = .coverVertical;
            (topController?.presentingViewController ?? topController)?.present(controller, animated: true, completion: nil);//(controller, animated: true, completion: nil);
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1;
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count;
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoStreamCell", for: indexPath);
        if let view = cell as? VideoStreamCell, let account = meet?.client.userBareJid {
            view.delegate = self;
            view.set(item: items[indexPath.item], account: account, publishersPublisher: $publisherByMid);
        }
        return cell;
    }
        
    
    override func loadView() {
//        let view = UIView();
        super.loadView();
        view.isOpaque = true;
//        let flowLayout = FlowLayout();
        (collectionView.collectionViewLayout as? FlowLayout)?.scrollDirection = .vertical;
        (collectionView.collectionViewLayout as? FlowLayout)?.itemSize = CGSize(width: 100, height: 100);
        (collectionView.collectionViewLayout as? FlowLayout)?.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
//        collectionView.collectionViewLayout = flowLayout;
        collectionView.delegate = collectonViewDelegate;
        collectionView.translatesAutoresizingMaskIntoConstraints = false;
        collectionView.allowsSelection = false;
        collectionView.autoresizesSubviews = true;
        view.addSubview(collectionView);
        
        buttonsStack.axis = .horizontal;
        buttonsStack.spacing = 40;
        buttonsStack.distribution = .equalSpacing;
     
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false;
        buttonsStack.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        buttonsStack.setContentHuggingPriority(.defaultHigh, for: .vertical);
        
        localVideoRenderer.translatesAutoresizingMaskIntoConstraints = false;
        localVideoRenderer.layer.cornerRadius = 5;
        localVideoRenderer.layer.backgroundColor = UIColor.red.cgColor;
        localVideoRenderer.layer.masksToBounds = true;
        view.addSubview(localVideoRenderer);
        
        endCallButton = RoundButton();
        endCallButton?.setImage(UIImage(systemName: "xmark"), for: .normal);
        endCallButton?.addTarget(self, action: #selector(endCall(_:)), for: .touchUpInside);
//        endCallButton?.hasBorder = false;
        endCallButton?.backgroundColor = UIColor.systemRed;
        endCallButton?.tintColor = UIColor.white;
        buttonsStack.addArrangedSubview(endCallButton!)
        
        muteButton = RoundButton();
        muteButton?.setImage(UIImage(systemName: "mic.slash.fill"), for: .normal);
        muteButton?.addTarget(self, action: #selector(muteClicked(_:)), for: .touchUpInside);
//        muteButton?.hasBorder = false;
        muteButton?.backgroundColor = UIColor.white.withAlphaComponent(0.1);
        muteButton?.tintColor = UIColor.white;
        buttonsStack.addArrangedSubview(muteButton!);
        
        moreButton = RoundButton();
        moreButton?.setImage(UIImage(systemName: "ellipsis"), for: .normal);
//        inviteButton?.hasBorder = false;
        moreButton?.backgroundColor = UIColor.white.withAlphaComponent(0.1);
        moreButton?.tintColor = UIColor.white;
        buttonsStack.addArrangedSubview(moreButton!);
        
        if #available(iOS 14.0, *) {
            moreButton?.menu = UIMenu(title: "", children: [
                UIAction(title: NSLocalizedString("Invite…", comment: "button label"), image: UIImage(systemName: "person.fill.badge.plus"), handler: { action in
                    self.inviteToCallClicked(action);
                }),
                UIAction(title: NSLocalizedString("Switch camera", comment: "button label"), image: UIImage(systemName: "arrow.triangle.2.circlepath.camera.fill"), handler: { action in
                    self.switchCamera();
                }),
                UIMenu(title: NSLocalizedString("Switch audio", comment: "button label"), image: UIImage(systemName: "speaker.wave.2"), children: [
                    switchAudioActions()
                ])
            ].reversed());
            moreButton?.showsMenuAsPrimaryAction = true;
        } else {
            moreButton?.addTarget(self, action: #selector(moreTapped(_:)), for: .touchUpInside);
        }
        view.addSubview(buttonsStack);
        
        localVideoRendererWidth = localVideoRenderer.widthAnchor.constraint(equalToConstant: 80);
                
        NSLayoutConstraint.activate([
            localVideoRendererWidth!,
            localVideoRenderer.heightAnchor.constraint(equalToConstant: 80),
            
            endCallButton!.widthAnchor.constraint(equalTo: endCallButton!.heightAnchor),
            endCallButton!.widthAnchor.constraint(equalToConstant: 40),

            muteButton!.widthAnchor.constraint(equalTo: muteButton!.heightAnchor),
            muteButton!.widthAnchor.constraint(equalToConstant: 40),
            
            moreButton!.widthAnchor.constraint(equalTo: moreButton!.heightAnchor),
            moreButton!.widthAnchor.constraint(equalToConstant: 40),
            
            view.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor,  constant: 0),
            view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: 0),
            view.layoutMarginsGuide.topAnchor.constraint(equalTo: collectionView.topAnchor, constant: 0),
            
            buttonsStack.topAnchor.constraint(lessThanOrEqualTo: collectionView.bottomAnchor, constant: 0),
            //buttonsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            //buttonsStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            buttonsStack.leadingAnchor.constraint(greaterThanOrEqualTo: localVideoRenderer.trailingAnchor, constant: 20),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            view.bottomAnchor.constraint(greaterThanOrEqualTo: buttonsStack.bottomAnchor, constant: 10),

            buttonsStack.centerYAnchor.constraint(equalTo: localVideoRenderer.centerYAnchor),
            localVideoRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            localVideoRenderer.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 10),
            view.bottomAnchor.constraint(equalTo: localVideoRenderer.bottomAnchor, constant: 10)
        ])
        
        localVideoRenderer.delegate = self;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        collectionView.register(VideoStreamCell.self, forCellWithReuseIdentifier: "VideoStreamCell");
        collectionView.dataSource = self;
    }
    
    @objc func endCall(_ sender: Any) {
        if let meet = self.meet {
            CallManager.instance?.endCall(meet);
        }
        self.dismiss(animated: true, completion: nil);
    }

    @objc func muteClicked(_ sender: Any) {
        muted = !muted;
        meet?.muted(value: muted);
    }

    @objc func inviteToCallClicked(_ sender: Any) {
        guard let meet = self.meet else {
            return;
        }
        let selector = InviteToMeetingViewController(style: .plain);
        selector.meet = meet;
        let navController = UINavigationController(rootViewController: selector);
        self.present(navController, animated: true, completion: nil);
    }
    
    @objc func moreTapped(_ sender: UIButton) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
        controller.popoverPresentationController?.sourceView = sender;
        controller.popoverPresentationController?.sourceRect = sender.bounds;
        
        controller.addAction(UIAlertAction(title: NSLocalizedString("Invite…", comment: "button label"), style: .default, handler: { action in
            self.inviteToCallClicked(sender);
        }))
        controller.addAction(UIAlertAction(title: NSLocalizedString("Switch camera", comment: "button label"), style: .default, handler: { action in
            self.switchCamera();
        }));
        controller.addAction(UIAlertAction(title: NSLocalizedString("Switch audio", comment: "button label"), style: .default, handler: { action in
            DispatchQueue.main.async {
                self.switchAudio(sender);
            }
        }))
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        
        self.present(controller, animated: true, completion: nil);
    }
    
    func switchCamera() {
        self.meet?.switchCameraDevice();
    }
    
    func switchAudio(_ sender: UIButton) {
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
    
    @available(iOS 14.0, *)
    func switchAudioActions() -> UIDeferredMenuElement {
        return UIDeferredMenuElement({ [weak self] completion in
            var items: [UIMenuElement] = [];
            
            for audioPort in self?.audioSession?.availableAudioPorts() ?? [] {
                var selected = false;
                
                switch audioPort {
                case .automatic:
                    break;
                case .builtin:
                    selected = AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver });
                case .speaker:
                    selected = AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker });
                case .custom(let port):
                    selected = AVAudioSession.sharedInstance().currentRoute.inputs.contains(where: { $0.portType == port.portType });
                }
                
                let item = UIAction(title: audioPort.label, image: audioPort.icon, state: selected ? .on : .off, handler: { action in
                    self?.audioSession?.set(outputMode: audioPort);
                });

                items.append(item);
            }

            completion(items.reversed());
        })
    }
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DispatchQueue.main.async {
            self.localVideoRendererWidth?.constant = (size.width * self.localVideoRenderer.frame.height) / size.height;
        }
    }

    private class FlowLayout: UICollectionViewFlowLayout {
            
        override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
            return true;
        }
            
        override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
            let context = super.invalidationContext(forBoundsChange: newBounds) as! UICollectionViewFlowLayoutInvalidationContext;
            context.invalidateFlowLayoutDelegateMetrics = true;
            return context;
        }
            
    }
    
    private class CollectionViewDelegate: NSObject, UICollectionViewDelegateFlowLayout {
        
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let itemsCount = collectionView.numberOfItems(inSection: indexPath.section);
 
            let spacing = (collectionViewLayout as! UICollectionViewFlowLayout).minimumLineSpacing;
            guard itemsCount > 1 else {
                return collectionView.frame.size;
            }
            
            let ratio = collectionView.frame.size.width / collectionView.frame.size.height;
            switch itemsCount {
            case 2:
                if ratio > 1 {
                    return CGSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height);
                } else {
                    return CGSize(width: collectionView.frame.size.width, height: collectionView.frame.size.height / 2 - spacing);
                }
            case 3:
                if ratio > 2 {
                    return CGSize(width: collectionView.frame.size.width, height: collectionView.frame.size.height / 3 - spacing);
                } else {
                    return CGSize(width: indexPath.item == 2 ? collectionView.frame.size.width : (collectionView.frame.size.width / 2 - spacing), height: collectionView.frame.size.height / 2 - spacing);
                }
            case 4:
                return CGSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 2 - spacing)
            case 5:
                if ratio > 1 {
                    let fullRow = indexPath.item < 3;
                    return CGSize(width: fullRow ? (collectionView.frame.size.width / 3 - spacing) : (collectionView.frame.size.width / 2 - spacing), height: collectionView.frame.size.height / 2 - spacing)
                } else {
                    let fullRow = indexPath.item < 4;
                    return CGSize(width: fullRow ? (collectionView.frame.size.width / 2 - spacing) : (collectionView.frame.size.width), height: collectionView.frame.size.height / 3 - spacing);
                }
            case 6:
                if ratio > 1 {
                    return CGSize(width: collectionView.frame.size.width / 3 - spacing, height: collectionView.frame.size.height / 2 - spacing);
                } else {
                    return CGSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 3 - spacing);
                }
            default:
                break;
            }

            guard itemsCount > 0 else {
                return collectionView.frame.size;
            }
            
            let columns = ceil(sqrt(CGFloat(itemsCount) * ratio));
            
            let itemAreaSize = (collectionView.frame.size.width / columns) - (collectionViewLayout as! UICollectionViewFlowLayout).minimumLineSpacing;
            return CGSize(width: itemAreaSize, height: itemAreaSize);
        }
        
        func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
            guard let controller = (collectionView.dataSource as? MeetController) else {
                return nil;
            }
            
            let item = controller.items[indexPath.item];
            guard let publisher = controller.publisherByMid[item.mid] else {
                return nil;
            }
            
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
                let kickOutAction = UIAction(title: NSLocalizedString("Kick out", comment: "button label"), image: nil, attributes: .destructive, handler: { action in
                    controller.meet?.deny(jids: [publisher.jid], completionHandler: { result in
                    })
                });
                return UIMenu(title: "", children: [kickOutAction]);
            })
        }
    }
    
    private struct Item {
        let mid: String;
        let videoTrack: RTCVideoTrack?;
        let receiverId: String;
    }
        
    private class VideoStreamCell: UICollectionViewCell, RTCVideoViewDelegate {
            
        weak var delegate: MeetController?;
            
        private let avatarView: AvatarView = AvatarView();
        private let nameLabel: UILabel = UILabel();
        private let nameBox = UIView();
        
        #if targetEnvironment(simulator)
        private let videoRenderer = RTCEAGLVideoView(frame: .zero);
        #else
        private let videoRenderer = RTCMTLVideoView(frame: .zero);
        #endif

        private var cancellables: Set<AnyCancellable> = [];
            
        private var avatarSize: NSLayoutConstraint?;
            
        private var videoTrack: RTCVideoTrack? {
            willSet {
                videoTrack?.remove(videoRenderer);
            }
            didSet {
                videoTrack?.add(videoRenderer);
            }
        }
            
        private var contact: Contact? {
            didSet {
                cancellables.removeAll();
                if let contact = contact {
                    contact.$displayName.map({ $0 as String? }).receive(on: DispatchQueue.main).assign(to: \.text, on: nameLabel).store(in: &cancellables);
                    contact.avatarPublisher.combineLatest(contact.$displayName).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] avatar, name in
                        self?.avatarView.set(name: name, avatar: avatar)
                    }).store(in: &cancellables);
                }
            }
        }
            
        private var item: Item?;
            
        private var publisherCancellable: AnyCancellable? {
            willSet {
                publisherCancellable?.cancel();
            }
        }
            
        func set(item: Item, account: BareJID, publishersPublisher: Published<[String:MeetModule.Publisher]>.Publisher) {
            self.videoTrack = item.videoTrack;
            self.item = item;
            publisherCancellable = publishersPublisher.map({ $0[item.mid]?.jid }).removeDuplicates().map({ j -> Contact? in
                if let jid = j {
                    return ContactManager.instance.contact(for: .init(account: account, jid: jid, type: .buddy));
                }
                return nil;
            }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] contact in
                self?.contact = contact;
            });
        }
            
        override init(frame: CGRect) {
            super.init(frame: frame);
            nameLabel.text = "";
            nameLabel.numberOfLines = 0;
            backgroundColor = UIColor.systemGray;
            layer.masksToBounds = true;
            layer.cornerRadius = 10;
                
            nameBox.translatesAutoresizingMaskIntoConstraints = false;
            nameBox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
            nameBox.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            avatarView.translatesAutoresizingMaskIntoConstraints = false;
            nameLabel.translatesAutoresizingMaskIntoConstraints = false;
            videoRenderer.translatesAutoresizingMaskIntoConstraints = false;
            #if targetEnvironment(simulator)
            videoRenderer.delegate = self;
            #else
            videoRenderer.videoContentMode = .scaleAspectFill;
            #endif

            nameLabel.textAlignment = .center;
            nameBox.backgroundColor = UIColor.darkGray.withAlphaComponent(0.9);
            nameLabel.font = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)
            //nameLabel.drawsBackground = true;
                
            addSubview(avatarView);
            addSubview(videoRenderer);
            nameBox.addSubview(nameLabel);
            addSubview(nameBox);
                
            avatarSize = avatarView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.65);
            avatarView.layer.masksToBounds = true;
                                
            #if targetEnvironment(simulator)
            let videoRendererConstraints: [NSLayoutConstraint] = [];
            #else
            let videoRendererConstraints: [NSLayoutConstraint] = [
                self.leadingAnchor.constraint(equalTo: videoRenderer.leadingAnchor),
                self.topAnchor.constraint(equalTo: videoRenderer.topAnchor),
                self.trailingAnchor.constraint(equalTo: videoRenderer.trailingAnchor),
                self.bottomAnchor.constraint(equalTo: videoRenderer.bottomAnchor)
            ]
            #endif
            
            NSLayoutConstraint.activate([
                avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
                self.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
                self.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),

                avatarSize!,
                
                nameBox.centerXAnchor.constraint(equalTo: nameLabel.centerXAnchor),
                nameBox.leadingAnchor.constraint(lessThanOrEqualTo: nameLabel.leadingAnchor),
                nameBox.topAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -6),
                nameBox.bottomAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
                    
                self.leadingAnchor.constraint(equalTo: nameBox.leadingAnchor),
                self.trailingAnchor.constraint(equalTo: nameBox.trailingAnchor),
                self.bottomAnchor.constraint(equalTo: nameBox.bottomAnchor)
            ] + videoRendererConstraints)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
                    
        override func removeFromSuperview() {
            self.videoTrack?.remove(videoRenderer);
        }
              
        private var videoSize: CGSize = .zero;
        
        func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize videoSize: CGSize) {
            #if targetEnvironment(simulator)
            self.videoSize = videoSize;
            self.setNeedsLayout();
            #endif
        }
        
        #if targetEnvironment(simulator)
        override func layoutSubviews() {
            super.layoutSubviews();
            
            guard videoSize.width > 0 && videoSize.height > 0 else {
                return;
            }

            var newFrame: CGRect = self.bounds;
            if videoSize.width > videoSize.height {
                newFrame.size = CGSize(width: (videoSize.width / videoSize.height) * newFrame.height, height: newFrame.height);
            } else {
                newFrame.size = CGSize(width: newFrame.width, height: (videoSize.height / videoSize.width) * newFrame.width);
            }

            videoRenderer.frame = newFrame;
            videoRenderer.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        #endif
        
    }
}
