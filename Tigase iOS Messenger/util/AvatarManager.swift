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

public class AvatarManager: EventHandler {
    
    public static let AVATAR_CHANGED = "messengerAvatarChanged";
    
    var defaultAvatar:UIImage;
    var cache = NSCache();
    
    var xmppService: XmppService {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    public init(xmppService: XmppService) {
        defaultAvatar = UIImage(named: "defaultAvatar")!;
        cache.countLimit = 20;
        cache.totalCostLimit = 20 * 1024 * 1024;
        xmppService.registerEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AvatarManager.vcardUpdated), name: DBVCardsCache.VCARD_UPDATED, object: nil);
    }
    
    public func getAvatar(jid:BareJID, account:BareJID) -> UIImage {
        let val = cache.objectForKey(jid.stringValue) as? AvatarHolder;
        if val?.beginContentAccess() ?? false {
            defer {
                val?.endContentAccess();
            }
            return val!.image;
        }
        
        let image = loadAvatar(jid) ?? defaultAvatar;
        
        // adding default avatar to cache to make sure we will not load data
        // from database when retrieving avatars for jids without avatar
        self.cache.setObject(AvatarHolder(image: image), forKey: jid.stringValue);
        return image;
    }
    
    public func handleEvent(event: Event) {
        switch event {
        case let cpc as PresenceModule.ContactPresenceChanged:
            guard cpc.presence.from != nil else {
                return;
            }
            updateAvatarHash(cpc.sessionObject.userBareJid!, jid: cpc.presence.from!.bareJid, photoHash: cpc.presence.vcardTempPhoto);
        default:
            break;
        }
    }
    
    func updateAvatarHash(account: BareJID, jid: BareJID, photoHash: String?) {
        guard photoHash != nil else {
            return;
        }

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)) {
            if !self.xmppService.dbVCardsCache.checkVCardPhotoHash(jid, hash: photoHash!) {
                if let vcardModule:VCardModule = self.xmppService.getClient(account)?.modulesManager?.getModule(VCardModule.ID) {
                    vcardModule.retrieveVCard(JID(jid), onSuccess: { (vcard) in
                        
                        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)) {
                            self.xmppService.dbVCardsCache.updateVCard(jid, vcard: vcard);
                        }
                        }, onError: { (errorCondition:ErrorCondition?) in
                            self.cache.removeObjectForKey(jid.stringValue);
                    });
                }
            }
        }
    }

    func loadAvatar(jid: BareJID) -> UIImage? {
        if let data = xmppService.dbVCardsCache.getPhoto(jid) {
            return UIImage(data: data);
        }
        return nil;
    }
    
    @objc func vcardUpdated(notification: NSNotification) {
        if let jid = notification.userInfo?["jid"] as? BareJID {
            cache.removeObjectForKey(jid.stringValue);
            NSNotificationCenter.defaultCenter().postNotificationName(AvatarManager.AVATAR_CHANGED, object: nil, userInfo: ["jid": jid]);
        }
    }
    
    func clearCache() {
        cache.removeAllObjects();
    }
    
    private class AvatarHolder: NSDiscardableContent {
        
        var counter = 0;
        var image: UIImage!;
        
        private init?(data: NSData?) {
            guard data != nil else {
                return nil;
            }
            
            image = UIImage(data: data!);
            guard image != nil else {
                return nil;
            }
        }
        
        private init(image: UIImage) {
            self.image = image;
        }
        
        @objc private func discardContentIfPossible() {
            if counter == 0 {
                image = nil;
            }
        }

        @objc private func isContentDiscarded() -> Bool {
            return image == nil;
        }
        
        @objc private func beginContentAccess() -> Bool {
            guard !isContentDiscarded() else {
                return false;
            }
            counter += 1;
            return true;
        }
        
        @objc private func endContentAccess() {
            counter -= 1;
        }
    }
}
