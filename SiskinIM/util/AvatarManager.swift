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
import TigaseSwift

open class AvatarManager {
    
    public static let AVATAR_CHANGED = Notification.Name("messengerAvatarChanged");
    public static let AVATAR_FOR_HASH_CHANGED = Notification.Name("avatarForHashChanged")
    public static let instance = AvatarManager(store: AvatarStore());
    
    var defaultAvatar: UIImage;
    var defaultGroupchatAvatar: UIImage;
    fileprivate let store: AvatarStore;
    fileprivate var dispatcher = QueueDispatcher(label: "avatar_manager", attributes: .concurrent);
    private var cache: [BareJID: AccountAvatarHashes] = [:];

    public init(store: AvatarStore) {
        defaultAvatar = UIImage(named: Appearance.current.isDark ? "defaultAvatarDark" : "defaultAvatarLight")!;
        defaultGroupchatAvatar = UIImage(named: Appearance.current.isDark ? "defaultGroupchatAvatarDark" : "defaultGroupchatAvatarLight")!;
        self.store = store;
        NotificationCenter.default.addObserver(self, selector: #selector(AvatarManager.vcardUpdated), name: DBVCardsCache.VCARD_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: Appearance.CHANGED, object: nil);
    }
    
    open func avatar(for jid: BareJID, on account: BareJID) -> UIImage? {
        return dispatcher.sync(flags: .barrier) {
            if let hash = self.avatars(on: account).avatarHash(for: jid) {
                return store.avatar(for: hash);
            }
            return nil;
        }
    }
    
    open func hasAvatar(withHash hash: String) -> Bool {
        return store.hasAvatarFor(hash: hash);
    }
    
    open func avatar(withHash hash: String) -> UIImage? {
        return store.avatar(for: hash);
    }
    
    open func storeAvatar(data: Data) -> String {
        let hash = Digest.sha1.digest(toHex: data)!;
        self.store.storeAvatar(data: data, for: hash);
        NotificationCenter.default.post(name: AvatarManager.AVATAR_FOR_HASH_CHANGED, object: hash);
        return hash;
    }
    
    open func updateAvatar(hash: String, forType type: AvatarType, forJid jid: BareJID, on account: BareJID) {
        dispatcher.async(flags: .barrier) {
            let oldHash = self.store.avatarHash(for: jid, on: account)[type];
            if oldHash == nil || oldHash! != hash {
                self.store.updateAvatar(hash: hash, type: type, for: jid, on: account, completionHandler: {
                    self.dispatcher.async(flags: .barrier) {
                        self.avatars(on: account).invalidateAvatarHash(for: jid);
                    }
                });
            }
        }
    }
    
    open func avatarHashChanged(for jid: BareJID, on account: BareJID, type: AvatarType, hash: String) {
        if hasAvatar(withHash: hash) {
            updateAvatar(hash: hash, forType: type, forJid: jid, on: account);
        } else {
            switch type {
            case .vcardTemp:
                XmppService.instance.refreshVCard(account: account, for: jid, onSuccess: nil, onError: nil);
            case .pepUserAvatar:
                self.retrievePepUserAvatar(for: jid, on: account, hash: hash);
            }
        }
    }
    
    @objc func vcardUpdated(_ notification: Notification) {
        guard let vcardItem = notification.object as? DBVCardsCache.VCardItem else {
            return;
        }

        DispatchQueue.global().async {
            guard let photo = vcardItem.vcard.photos.first else {
                return;
            }

            AvatarManager.fetchData(photo: photo) { data in
                guard data != nil else {
                    return;
                }

                let hash = self.storeAvatar(data: data!);
                self.updateAvatar(hash: hash, forType: .vcardTemp, forJid: vcardItem.jid, on: vcardItem.account);
            }
        }
    }

    @objc func appearanceChanged(_ notification: Notification) {
        self.defaultAvatar = UIImage(named: Appearance.current.isDark ? "defaultAvatarDark" : "defaultAvatarLight")!;
        self.defaultGroupchatAvatar = UIImage(named: Appearance.current.isDark ? "defaultGroupchatAvatarDark" : "defaultGroupchatAvatarLight")!;
    }
    
    func retrievePepUserAvatar(for jid: BareJID, on account: BareJID, hash: String) {
        guard let pepModule: PEPUserAvatarModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PEPUserAvatarModule.ID) else {
            return;
        }

        pepModule.retrieveAvatar(from: jid, itemId: hash, onSuccess: { (jid, hash, photoData) in
            guard let data = photoData else {
                return;
            }
            self.store.storeAvatar(data: data, for: hash);
            self.updateAvatar(hash: hash, forType: .pepUserAvatar, forJid: jid, on: account);
        }, onError: nil);
    }
    
    func clearCache() {
        store.clearCache();
    }
    
    private func avatars(on account: BareJID) -> AvatarManager.AccountAvatarHashes {
        if let avatars = self.cache[account] {
            return avatars;
        }
        let avatars = AccountAvatarHashes(store: store, account: account);
        self.cache[account] = avatars;
        return avatars;
    }

    static func fetchData(photo: VCard.Photo, completionHandler: @escaping (Data?)->Void) {
        if let data = photo.binval {
            completionHandler(Data(base64Encoded: data, options: Data.Base64DecodingOptions.ignoreUnknownCharacters));
        } else if let uri = photo.uri {
            if uri.hasPrefix("data:image") && uri.contains(";base64,") {
                let idx = uri.index(uri.firstIndex(of: ",")!, offsetBy: 1);
                let data = String(uri[idx...]);
                print("got avatar:", data);
                completionHandler(Data(base64Encoded: data, options: Data.Base64DecodingOptions.ignoreUnknownCharacters));
            } else {
                let url = URL(string: uri)!;
                let task = URLSession.shared.dataTask(with: url) { (data, response, err) in
                    completionHandler(data);
                }
                task.resume();
            }
        } else {
            completionHandler(nil);
        }
    }

    private class AccountAvatarHashes {

        private static let AVATAR_TYPES_ORDER: [AvatarType] = [.pepUserAvatar, .vcardTemp];
        
        private var avatarHashes: [BareJID: Optional<String>] = [:];

        private let store: AvatarStore;
        let account: BareJID;
        
        init(store: AvatarStore, account: BareJID) {
            self.store = store;
            self.account = account;
        }
        
        func avatarHash(for jid: BareJID) -> String? {
            if let hash = avatarHashes[jid] {
                return hash;
            }
            
            let hashes: [AvatarType:String] = store.avatarHash(for: jid, on: account);
        
            for type in AccountAvatarHashes.AVATAR_TYPES_ORDER {
                if let hash = hashes[type] {
                    if store.hasAvatarFor(hash: hash) {
                        avatarHashes[jid] = .some(hash);
                        return hash;
                    }
                }
            }
            avatarHashes[jid] = .none;
            return nil;
        }
        
        func invalidateAvatarHash(for jid: BareJID) {
            avatarHashes.removeValue(forKey: jid);
            NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: self, userInfo: ["account": account, "jid": jid]);
        }
        
    }

}
