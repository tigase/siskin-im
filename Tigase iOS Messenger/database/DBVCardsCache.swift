//
// DBVCardsCache.swift
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

import Foundation
import TigaseSwift

open class DBVCardsCache {
    
    open static let VCARD_UPDATED = Notification.Name("messengerVCardUpdated");
    
    let dbConnection: DBConnection;
    
    fileprivate lazy var updateVCardStmt:DBStatement! = try? self.dbConnection.prepareStatement("UPDATE vcards_cache SET data = :data, avatar = :avatar, avatar_hash = :avatar_hash, timestamp = :timestamp WHERE jid = :jid");
    fileprivate lazy var insertVCardStmt:DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO vcards_cache (jid, data, avatar, avatar_hash, timestamp) VALUES(:jid, :data, :avatar, :avatar_hash, :timestamp)");
    fileprivate lazy var chechPhotoHashStmt:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM vcards_cache WHERE jid = :jid AND avatar_hash IS NOT NULL AND avatar_hash = :avatar_hash");
    fileprivate lazy var getPhotoStmt:DBStatement! = try? self.dbConnection.prepareStatement("SELECT avatar FROM vcards_cache WHERE jid = :jid");
    fileprivate lazy var getVCardStmt:DBStatement! = try? self.dbConnection.prepareStatement("SELECT data FROM vcards_cache WHERE jid = :jid");
    
    public init(dbConnection: DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    open func updateVCard(_ jid: BareJID, vcard: VCardModule.VCard?) {
        let avatar_data = vcard?.photoValBinary;
        let avatar_hash:String? = Digest.sha1.digestToHex(avatar_data);
        
        let params:[String:Any?] = ["jid" : jid, "data": vcard, "avatar": avatar_data, "avatar_hash": avatar_hash, "timestamp": NSDate()];
        dbConnection.dispatch_async_db_queue() {
            if try! self.updateVCardStmt.update(params) == 0 {
                _ = try! self.insertVCardStmt.insert(params);
            }
        }
        NotificationCenter.default.post(name: DBVCardsCache.VCARD_UPDATED, object: self, userInfo: ["jid": jid]);
    }
    
    open func getVCard(_ jid: BareJID) -> VCardModule.VCard? {
        
        if let data:String = dbConnection.dispatch_sync_with_result_local_queue({
            return try! self.getVCardStmt.query(jid)?["data"];
        }) {
            if let vcardEl = Element.fromString(data) {
                return VCardModule.VCard(element: vcardEl);
            }
        }
        return nil;
    }
    
    open func checkVCardPhotoHash(_ jid: BareJID, hash: String) -> Bool {
        let params:[String:Any?] = ["jid": jid, "avatar_hash": hash.lowercased()];
        let count = try! chechPhotoHashStmt.scalar(params);
        return count == 1;
    }
    
    open func getPhoto(_ jid: BareJID) -> Data? {
        return dbConnection.dispatch_sync_with_result_local_queue(){
            let cursor = try! self.getPhotoStmt.query(jid);
            return cursor?["avatar"];
        }
    }
}
