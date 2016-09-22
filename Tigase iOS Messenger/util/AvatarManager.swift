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
    fileprivate var cache = NSCache<NSString, AvatarHolder>();
    
    var xmppService: XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    public init(xmppService: XmppService) {
        defaultAvatar = UIImage(named: "defaultAvatar")!;
        cache.countLimit = 20;
        cache.totalCostLimit = 20 * 1024 * 1024;
        xmppService.registerEventHandler(self, for: PresenceModule.ContactPresenceChanged.TYPE);
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
        
        let image = loadAvatar(for: jid) ?? defaultAvatar;
        
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
            updateAvatarHash(account: cpc.sessionObject.userBareJid!, for: cpc.presence.from!.bareJid, photoHash: cpc.presence.vcardTempPhoto);
        default:
            break;
        }
    }
    
    func updateAvatarHash(account: BareJID, for jid: BareJID, photoHash: String?) {
        guard photoHash != nil else {
            return;
        }

        DispatchQueue.global(qos: .background).async() {
            if !self.xmppService.dbVCardsCache.checkVCardPhotoHash(for: jid, hash: photoHash!) {
                if let vcardModule:VCardModule = self.xmppService.getClient(forJid: account)?.modulesManager?.getModule(VCardModule.ID) {
                    vcardModule.retrieveVCard(from: JID(jid), onSuccess: { (vcard) in
                        
                        DispatchQueue.global(qos: .background).async() {
                            self.xmppService.dbVCardsCache.updateVCard(for: jid, vcard: vcard);
                        }
                        }, onError: { (errorCondition:ErrorCondition?) in
                            self.cache.removeObject(forKey: jid.stringValue as NSString);
                    });
                }
            }
        }
    }

    func loadAvatar(for jid: BareJID) -> UIImage? {
        if let data = xmppService.dbVCardsCache.getPhoto(for: jid) {
            return UIImage(data: data);
        }
        return nil;
    }
    
    @objc func vcardUpdated(_ notification: NSNotification) {
        if let jid = notification.userInfo?["jid"] as? BareJID {
            cache.removeObject(forKey: jid.stringValue as NSString);
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
