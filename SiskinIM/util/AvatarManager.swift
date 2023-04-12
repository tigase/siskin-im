//
// AvatarManager.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import Martin
import Combine
import TigaseLogging
import CryptoKit
import Shared

struct AvatarWeakRef {
    weak var avatar: Avatar?;
}

public class Avatar: Publisher, ObservableObject {

    private struct AvatarSubscription: Subscription {
        
        let combineIdentifier = CombineIdentifier();
        
        private let avatar: Avatar;
        private let subscription: Subscription;
        
        init(avatar: Avatar, subscription: Subscription) {
            self.avatar = avatar;
            self.subscription = subscription;
        }
        
        @inlinable
        func request(_ demand: Subscribers.Demand) {
            subscription.request(demand);
        }
        
        @inlinable
        func cancel() {
            subscription.cancel();
        }
        
    }

    private struct AvatarSubscriber<Input,Failure: Error>: Subscriber {
               
        let combineIdentifier = CombineIdentifier();

        private let receiveInput: (Input) -> Subscribers.Demand;
        private let receiveCompletion: (Subscribers.Completion<Failure>) -> Void;
        private let receiveSubscription: (Subscription)->Void;
        
        init<S: Subscriber>(avatar: Avatar, subscriber: S) where Input == S.Input, Failure == S.Failure {
            self.receiveInput = { input in
                subscriber.receive(input);
            }
            self.receiveCompletion = { completion in
                subscriber.receive(completion: completion);
            }
            self.receiveSubscription = { subscription in
                subscriber.receive(subscription: AvatarSubscription(avatar: avatar, subscription: subscription));
            }
        }
        
        @inlinable
        func receive(subscription: Subscription) {
            receiveSubscription(subscription);
        }
        
        @inlinable
        func receive(_ input: Input) -> Subscribers.Demand {
            receiveInput(input);
        }
        
        @inlinable
        func receive(completion: Subscribers.Completion<Failure>) {
            receiveCompletion(completion);
        }
        
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, UIImage? == S.Input {
        self.publisher!.receive(subscriber: AvatarSubscriber(avatar: self, subscriber: subscriber));
    }
    
    public typealias Output = UIImage?
    public typealias Failure = Never
    
    public enum Hash: Equatable {
        case notReady
        case hash(String?)
    }
    
    private let key: Key;

    @Published
    public var hash: Hash = .notReady;
    private var publisher: AnyPublisher<UIImage?,Never>?;
    
    init(key: Key) {
        self.key = key;
        self.publisher = $hash.filter({ .notReady != $0 }).map({
            switch $0 {
            case .notReady:
                return nil;
            case .hash(let hash):
                if let hash {
                    return AvatarManager.instance.avatar(withHash: hash);
                } else {
                    return nil;
                }
            }
        }).removeDuplicates().eraseToAnyPublisher();
    }

    deinit {
        AvatarManager.instance.releasePublisher(for: key);
    }
    
    struct Key: Hashable, CustomStringConvertible {
        let account: BareJID;
        let jid: BareJID;
        let mucNickname: String?;
        
        var description: String {
            return "Key(account: \(account), jid: \(jid), nick: \(mucNickname ?? ""))";
        }
    }

}

class AvatarManager {

    public static let instance = AvatarManager();

    private let store = AvatarStore();
    public var defaultAvatar: UIImage {
        return UIImage(named: "defaultAvatar")!;
    }
    public var defaultGroupchatAvatar: UIImage {
        return UIImage(named: "defaultGroupchatAvatar")!;
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AvatarManager");
    
    fileprivate var queue = DispatchQueue(label: "avatar_manager", attributes: .concurrent);

    public init() {
        NotificationCenter.default.addObserver(self, selector: #selector(vcardUpdated), name: DBVCardStore.VCARD_UPDATED, object: nil);
    }

    private var avatars: [Avatar.Key: AvatarWeakRef] = [:];
    open func avatarPublisher(for key: Avatar.Key) -> Avatar {
        return queue.sync(flags: .barrier) {
            guard let avatar = avatars[key]?.avatar else {
                let avatar = Avatar(key: key);
                DispatchQueue.global(qos: .userInitiated).async {
                    let start = Date();
                    avatar.hash = .hash(self.avatarHash(for: key.jid, on: key.account, withNickname: key.mucNickname));
                    let end = Date();
                    print("avatar loaded in: \(end.timeIntervalSince(start) * 1000) ms")
                }
                avatars[key] = AvatarWeakRef(avatar: avatar);
                return avatar;
            }
            return avatar;
        }
    }
    
    open func existingAvatarPublisher(for key: Avatar.Key) -> Avatar? {
        return queue.sync {
            return avatars[key]?.avatar;
        }
    }
    
    open func releasePublisher(for key: Avatar.Key) {
        queue.async(flags: .barrier) {
            self.avatars.removeValue(forKey: key);
        }
    }
    
    private func avatarHash(for jid: BareJID, on account: BareJID, withNickname nickname: String?) -> String? {
        if let nickname = nickname {
            guard let room = DBChatStore.instance.conversation(for: account, with: jid) as? Room else {
                return nil;
            }
            
            guard let occupant = room.occupant(nickname: nickname) else {
                return nil;
            }
            
            guard let hash = occupant.presence.vcardTempPhoto else {
                guard let occuapntJid = occupant.jid?.bareJid else {
                    return nil;
                }
                
                return store.avatarHash(for: occuapntJid, on: account).first?.hash;
            }
            
            return hash;
        } else {
            return store.avatarHash(for: jid, on: account).first?.hash;//avatars(on: account).avatarHash(for: jid);
        }
    }
    
    // TODO: consider reviewing usage and replacing this code with async-await
    open func avatar(for jid: BareJID, on account: BareJID) -> UIImage? {
        guard let hash = store.avatarHash(for: jid, on: account).first?.hash else {
            return nil;
        }
        return store.avatar(for: hash);
    }
    
    open func hasAvatar(withHash hash: String) -> Bool {
        return store.hasAvatar(forHash: hash);
    }
    
    // TODO: consider reviewing usage and replacing this code with async-await
    open func avatar(withHash hash: String) -> UIImage? {
        return store.avatar(for: hash);
    }
        
    open func storeAvatar(data: Data) -> String {
        let hash = Insecure.SHA1.hash(toHex: data);
        self.store.storeAvatar(data: data, for: hash);
       return hash;
    }
    
    open func updateAvatar(hash: String, forType type: AvatarType, forJid jid: BareJID, on account: BareJID) {
        guard self.store.updateAvatarHash(for: jid, on: account, hash: .init(type: type, hash: hash)) else {
            return;
        }
        guard self.store.avatarHash(for: jid, on: account).first?.type != type else {
            return;
        }
        
        guard let avatar = self.existingAvatarPublisher(for: .init(account: account, jid: jid, mucNickname: nil)) else {
            return;
        }
        
        avatar.hash = .hash(hash);
    }
    
    public func avatarUpdated(hash: String?, for jid: BareJID, on account: BareJID, withNickname nickname: String) {
        if let avatar = self.existingAvatarPublisher(for: .init(account: account, jid: jid, mucNickname: nickname)) {
            if hash == nil {
                if let room = DBChatStore.instance.conversation(for: account, with: jid) as? Room, let occupantJid = room.occupant(nickname: nickname)?.jid?.bareJid {
                    avatar.hash = .hash(store.avatarHash(for: occupantJid, on: account).first?.hash);
                } else {
                    avatar.hash = .hash(hash);
                }
            } else {
                avatar.hash = .hash(hash);
            }
        }
    }
    
    open func avatarHashChanged(for jid: BareJID, on account: BareJID, type: AvatarType, hash: String) {
        if hasAvatar(withHash: hash) {
            updateAvatar(hash: hash, forType: type, forJid: jid, on: account);
        } else {
            switch type {
            case .vcardTemp:
                Task {
                    try await VCardManager.instance.refreshVCard(for: jid, on: account);
                }
            case .pepUserAvatar:
                self.retrievePepUserAvatar(for: jid, on: account, hash: hash);
            }
        }
    }

    
    @objc func vcardUpdated(_ notification: Notification) {
        guard let vcardItem = notification.object as? DBVCardStore.VCardItem else {
            return;
        }

        guard let photo = vcardItem.vcard.photos.first else {
            return;
        }
        
        Task.detached {
            let data = try await VCardManager.fetchPhoto(photo: photo);
            let hash = self.storeAvatar(data: data);
            self.updateAvatar(hash: hash, forType: .vcardTemp, forJid: vcardItem.jid, on: vcardItem.account);
        }
    }

    func retrievePepUserAvatar(for jid: BareJID, on account: BareJID, hash: String) {
        guard let pepModule = XmppService.instance.getClient(for: account)?.module(.pepUserAvatar) else {
            return;
        }

        pepModule.retrieveAvatar(from: jid, itemId: hash, completionHandler: { result in
            switch result {
            case .success(let avatarData):
                Task.detached {
                    self.store.storeAvatar(data: avatarData.data, for: hash);
                    self.updateAvatar(hash: hash, forType: .pepUserAvatar, forJid: jid, on: account);
                }
            case .failure(let error):
                self.logger.error("could not retrieve avatar from: \(jid), item id: \(hash), got error: \(error.description, privacy: .public)");
            }
        });
    }
    
    public func clearCache() {
        store.clearCache();
    }

}

enum AvatarResult {
    case some(AvatarType, String)
    case none
}
