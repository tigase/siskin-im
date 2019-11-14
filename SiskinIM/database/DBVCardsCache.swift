//
// DBVCardsCache.swift
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

import Foundation
import Shared
import TigaseSwift

open class DBVCardsCache {
    
    public static let VCARD_UPDATED = Notification.Name("messengerVCardUpdated");
    
    let dbConnection: DBConnection;
    
    fileprivate lazy var updateVCardStmt:DBStatement! = try? self.dbConnection.prepareStatement("UPDATE vcards_cache SET data = :data, timestamp = :timestamp WHERE jid = :jid");
    fileprivate lazy var insertVCardStmt:DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO vcards_cache (jid, data, timestamp) VALUES(:jid, :data, :timestamp)");
    fileprivate lazy var getVCardStmt:DBStatement! = try? self.dbConnection.prepareStatement("SELECT data FROM vcards_cache WHERE jid = :jid");
    
    public init(dbConnection: DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    open func updateVCard(for jid: BareJID, on account: BareJID, vcard: VCard?) {
        let params:[String:Any?] = ["jid" : jid, "data": vcard?.toVCard4(), "timestamp": NSDate()];
        updateVCardStmt.dispatcher.async {
            if try! self.updateVCardStmt.update(params) == 0 {
                _ = try! self.insertVCardStmt.insert(params);
            }
            if vcard != nil {
                NotificationCenter.default.post(name: DBVCardsCache.VCARD_UPDATED, object: VCardItem(vcard: vcard!, for: jid, on: account));
            }
        }
    }
    
    open func getVCard(for jid: BareJID) -> VCard? {
        do {
            if let data:String = try self.getVCardStmt.findFirst(jid, map: { cursor in cursor["data"] }) {
                if let vcardEl = Element.from(string: data) {
                    return VCard(vcard4: vcardEl) ?? VCard(vcardTemp: vcardEl);
                }
            }
        } catch {
            // we cannot do anything, so let's ignore for now...
        }
        return nil;
    }
    
    open func fetchPhoto(for jid: BareJID, callback: @escaping (Data?)->Void) {
        if let photo = getVCard(for: jid)?.photos.first {
            fetchPhoto(photo: photo, callback: callback);
        } else {
            callback(nil);
        }
    }
    
    open func fetchPhoto(photo: VCard.Photo, callback: @escaping (Data?)->Void) {
        if photo.binval != nil {
            callback(Data(base64Encoded: photo.binval!, options: NSData.Base64DecodingOptions.ignoreUnknownCharacters));
        } else if photo.uri != nil {
            if photo.uri!.hasPrefix("data:image") && photo.uri!.contains(";base64,") {
                if let idx = photo.uri!.firstIndex(of: ",") {
                    let data = photo.uri!.suffix(from: photo.uri!.index(after: idx));
                    callback(Data(base64Encoded: String(data), options: NSData.Base64DecodingOptions.ignoreUnknownCharacters));
                    return;
                }
            }
            if let url = URL(string: photo.uri!) {
                let task = URLSession.shared.dataTask(with: url) { (data, response, err) in
                    callback(data);
                };
                task.resume();
            }
        } else {
            callback(nil);
        }
    }
    
    class VCardItem {
        
        let vcard: VCard;
        let account: BareJID;
        let jid: BareJID;
        
        init(vcard: VCard, for jid: BareJID, on account: BareJID) {
            self.vcard = vcard;
            self.jid = jid;
            self.account = account;
        }
    }
}
