//
// AvatarManager.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

open class AvatarManager: EventHandler {
    
    open static let AVATAR_CHANGED = Notification.Name("messengerAvatarChanged");
    
    var defaultAvatar:UIImage;
    var store: AvatarStore;
    fileprivate var cache = NSCache<NSString, AvatarHolder>();
    
    var xmppService: XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    public init(xmppService: XmppService, store: AvatarStore) {
        defaultAvatar = UIImage(named: "defaultAvatar")!;
        cache.countLimit = 20;
        cache.totalCostLimit = 20 * 1024 * 1024;
        self.store = store;
        xmppService.registerEventHandler(self, for: PresenceModule.ContactPresenceChanged.TYPE, PEPUserAvatarModule.AvatarChangedEvent.TYPE);
        NotificationCenter.default.addObserver(self, selector: #selector(AvatarManager.vcardUpdated), name: DBVCardsCache.VCARD_UPDATED, object: nil);
    }
    
    open func getAvatar(for jid:BareJID, account:BareJID) -> UIImage {
        let val = cache.object(forKey: jid.stringValue as NSString);
        if val?.beginContentAccess() ?? false {
            defer {
                val?.endContentAccess();
            }
            return val!.image;
        }
        
        let image = loadAvatar(for: jid, on: account) ?? defaultAvatar;
        
        // adding default avatar to cache to make sure we will not load data
        // from database when retrieving avatars for jids without avatar
        self.cache.setObject(AvatarHolder(image: image), forKey: jid.stringValue as NSString);
        return image;
    }
    
    open func handle(event: Event) {
        switch event {
        case let cpc as PresenceModule.ContactPresenceChanged:
            guard cpc.presence.from != nil else {
                return;
            }
            updateAvatarHashFromVCard(account: cpc.sessionObject.userBareJid!, for: cpc.presence.from!.bareJid, photoHash: cpc.presence.vcardTempPhoto);
        case let ace as PEPUserAvatarModule.AvatarChangedEvent:
            let item = ace.info.first(where: { (info) -> Bool in
                return info.url == nil;
            })
            updateAvatarHashFromUserAvatar(account: ace.sessionObject.userBareJid!, for: ace.jid.bareJid, photoHash: item?.id);
        default:
            break;
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
            
            self.xmppService.dbVCardsCache.fetchPhoto(for: jid) { (photoData) in
                let hash = Digest.sha1.digest(toHex: photoData);
                
                if hash != photoHash {
                    self.xmppService.refreshVCard(account: account, for: jid, onSuccess: { (vcard) in
                        
                    }, onError: { (errorCondition) in
                        self.cache.removeObject(forKey: jid.stringValue as NSString);
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
            self.xmppService.dbVCardsCache.fetchPhoto(for: jid) { (data) in
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
        if let pepUserAvatarModule: PEPUserAvatarModule = self.xmppService.getClient(forJid: account)?.modulesManager.getModule(PEPUserAvatarModule.ID) {
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
            self.xmppService.dbVCardsCache.fetchPhoto(for: jid) { (data) in
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
            self.cache.removeObject(forKey: jid.stringValue as NSString);
            NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: nil, userInfo: ["jid": jid]);
        }
    }
    
    func clearCache() {
        cache.removeAllObjects();
    }
    
    fileprivate class AvatarHolder: NSDiscardableContent {
        
        var counter = 0;
        var image: UIImage!;
        
        fileprivate init?(data: NSData?) {
            guard data != nil else {
                return nil;
            }
            
            image = UIImage(data: data! as Data);
            guard image != nil else {
                return nil;
            }
        }
        
        fileprivate init(image: UIImage) {
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
