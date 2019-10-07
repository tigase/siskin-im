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
    public static let instance = AvatarManager(store: AvatarStore());
    
    var defaultAvatar: UIImage;
    var defaultGroupchatAvatar: UIImage;
    var store: AvatarStore;
    fileprivate var cache = NSCache<NSString, AvatarHolder>();

    public init(store: AvatarStore) {
        defaultAvatar = UIImage(named: Appearance.current.isDark ? "defaultAvatarDark" : "defaultAvatarLight")!;
        defaultGroupchatAvatar = UIImage(named: Appearance.current.isDark ? "defaultGroupchatAvatarDark" : "defaultGroupchatAvatarLight")!;
        cache.countLimit = 20;
        cache.totalCostLimit = 20 * 1024 * 1024;
        self.store = store;
        NotificationCenter.default.addObserver(self, selector: #selector(AvatarManager.vcardUpdated), name: DBVCardsCache.VCARD_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: Appearance.CHANGED, object: nil);
    }
    
    open func getAvatar(for jid:BareJID, account:BareJID, orDefault: UIImage?) -> UIImage? {
        let key = createKey(jid: jid);
        let val = cache.object(forKey: key as NSString);
        if val?.beginContentAccess() ?? false {
            defer {
                val?.endContentAccess();
            }
            return val!.image ?? orDefault;
        }
        
        if let image = loadAvatar(for: jid, on: account) {
            self.cache.setObject(AvatarHolder(image: image), forKey: key as NSString);
            return image;
        } else {
            self.cache.setObject(AvatarHolder.EMPTY, forKey: key as NSString);
            return orDefault;
        }
    }
        
    func updateAvatarHashFromVCard(account: BareJID, for jid: BareJID, photoHash: String?) {
        guard photoHash != nil else {
            return;
        }
        
        DispatchQueue.global(qos: .background).async() {
            guard !self.store.isAvatarAvailable(hash: photoHash!) else {
                return;
            }
        
            XmppService.instance.dbVCardsCache.fetchPhoto(for: jid) { (photoData) in
                let hash = Digest.sha1.digest(toHex: photoData);
                
                if hash != photoHash {
                    XmppService.instance.refreshVCard(account: account, for: jid, onSuccess: { (vcard) in
                        
                    }, onError: { (errorCondition) in
                        let key = self.createKey(jid: jid);
                        self.cache.removeObject(forKey: key as NSString);
                    });
                } else if hash != nil {
                    self.store.storeAvatar(data: photoData!, hash: hash!);
                    self.notifyAvatarChanged(hash: hash!, type: .vcardTemp, for: jid, on: account);
                }
            }
        }
    }
    
    func updateAvatarHashFromUserAvatar(account: BareJID, for jid: BareJID, photoHash: String?) {
        DispatchQueue.global(qos: .background).async() {
            guard photoHash != nil else {
                self.notifyAvatarChanged(hash: nil, type: .pepUserAvatar, for: jid, on: account);
                return;
            }
            guard !self.store.isAvatarAvailable(hash: photoHash!) else {
                return;
            }
            self.retrievePepUserAvatar(for: jid, on: account, photoHash: photoHash!);
        }
    }

    func loadAvatar(for jid: BareJID, on account: BareJID) -> UIImage? {
        let hashes = store.getAvatarHashes(for: jid, on: account);
        if let hash = hashes[AvatarType.pepUserAvatar] {
            if let image = store.getAvatar(hash: hash) {
                return image;
            }
            DispatchQueue.global(qos: .background).async {
                self.retrievePepUserAvatar(for: jid, on: account, photoHash: hash);
            }
        }
        if let hash = hashes[AvatarType.vcardTemp] {
            if let image = store.getAvatar(hash: hash) {
                return image;
            }
            XmppService.instance.dbVCardsCache.fetchPhoto(for: jid) { (data) in
                if data != nil {
                    self.store.storeAvatar(data: data!, hash: hash);
                    self.notifyAvatarChanged(hash: hash, type: .vcardTemp, for: jid, on: account);
                }
            }
            return store.getAvatar(hash: hash);
        }
        
        return nil;
    }

    func retrievePepUserAvatar(for jid: BareJID, on account: BareJID, photoHash: String) {
        if let pepUserAvatarModule: PEPUserAvatarModule = XmppService.instance.getClient(forJid: account)?.modulesManager.getModule(PEPUserAvatarModule.ID) {
            pepUserAvatarModule.retrieveAvatar(from: jid, itemId: photoHash, onSuccess: { (jid, hash, photoData) in
                DispatchQueue.global(qos: .background).async {
                    guard photoData != nil else  {
                        self.notifyAvatarChanged(hash: nil, type: .pepUserAvatar, for: jid, on: account);
                        return;
                    }
                    self.store.storeAvatar(data: photoData!, hash: hash);
                    self.notifyAvatarChanged(hash: hash, type: .pepUserAvatar, for: jid, on: account);
                }
                }, onError: nil);
        }
    }
    
    @objc func vcardUpdated(_ notification: NSNotification) {
        if let jid = notification.userInfo?["jid"] as? BareJID, let account = notification.userInfo?["account"] as? BareJID {
            XmppService.instance.dbVCardsCache.fetchPhoto(for: jid) { (data) in
                let hash = Digest.sha1.digest(toHex: data);
                if data != nil {
                    self.store.storeAvatar(data: data!, hash: hash!);
                }
                self.notifyAvatarChanged(hash: hash, type: .vcardTemp, for: jid, on: account);
            }
        }
    }
    
    func notifyAvatarChanged(hash: String?, type: AvatarType, for jid: BareJID, on account: BareJID) {
        self.store.updateAvatar(hash: hash, type: type, for: jid, on: account) {
            let key = self.createKey(jid: jid);
            self.cache.removeObject(forKey: key as NSString);
            NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: nil, userInfo: ["jid": jid, "account": account]);
        }
    }
    
    func clearCache() {
        cache.removeAllObjects();
    }
    
    fileprivate func createKey(jid: BareJID) -> String {
        return jid.stringValue.lowercased();
    }
    
    @objc func appearanceChanged(_ notification: Notification) {
        self.defaultAvatar = UIImage(named: Appearance.current.isDark ? "defaultAvatarDark" : "defaultAvatarLight")!;
        self.defaultGroupchatAvatar = UIImage(named: Appearance.current.isDark ? "defaultGroupchatAvatarDark" : "defaultGroupchatAvatarLight")!;
        self.cache.removeAllObjects();
    }
    
    fileprivate class AvatarHolder: NSDiscardableContent {
        
        fileprivate static let EMPTY = AvatarHolder(image: nil);
        
        var counter = 0;
        var image: UIImage?;
        
        fileprivate init?(data: NSData?) {
            guard data != nil else {
                return nil;
            }
            
            image = UIImage(data: data! as Data);
            guard image != nil else {
                return nil;
            }
        }
        
        fileprivate init(image: UIImage?) {
            self.image = image;
        }
        
        @objc fileprivate func discardContentIfPossible() {
            if counter == 0 {
                image = nil;
            }
        }

        @objc fileprivate func isContentDiscarded() -> Bool {
            return image == nil;
        }
        
        @objc fileprivate func beginContentAccess() -> Bool {
            guard !isContentDiscarded() else {
                return false;
            }
            counter += 1;
            return true;
        }
        
        @objc fileprivate func endContentAccess() {
            counter -= 1;
        }
    }
}
