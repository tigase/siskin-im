//
// AvatarStore.swift
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

open class AvatarStore {
    
    fileprivate let avatarCacheUrl: URL;
    fileprivate let dbConnection: DBConnection;
    
    fileprivate let dispatcher: QueueDispatcher;
    
    private let cache = NSCache<NSString,UIImage>();
    
    fileprivate lazy var findAvatarHashForJidStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT type, hash FROM avatars_cache WHERE jid = :jid AND account = :account");
    fileprivate lazy var deleteAvatarHashForJidStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM avatars_cache WHERE jid = :jid AND account = :account AND (:type IS NULL OR type = :type)");
    fileprivate lazy var insertAvatarHashForJidStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO avatars_cache (jid, account, hash, type) VALUES (:jid,:account,:hash,:type)");
    
    public convenience init() {
        self.init(dbConnection: DBConnection.main);
    }
    
    public init(dbConnection: DBConnection) {
        self.dispatcher = QueueDispatcher(label: "AvatarStore", attributes: .concurrent);
        self.dbConnection = dbConnection;
        
        avatarCacheUrl = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("avatars", isDirectory: true);
    }
    
    open func hasAvatarFor(hash: String) -> Bool {
        return dispatcher.sync {
            return FileManager.default.fileExists(atPath: avatarCacheUrl.appendingPathComponent(hash).path);
        }
    }
    
    open func avatarHash(for jid: BareJID, on account: BareJID) -> [AvatarType:String] {
        let params = ["account": account, "jid": jid] as [String : Any?];
        var hashes: [AvatarType:String] = [:];
        try! self.findAvatarHashForJidStmt.query(params, forEach: { (cursor) -> Void in
            guard let typeRawValue: String = cursor["type"], let hash: String = cursor["hash"] else {
                return;
            }
            guard let avatarType = AvatarType(rawValue: typeRawValue) else {
                return;
            }
            hashes[avatarType] = hash;
        });
        return hashes;
    }
    
    open func avatar(for hash: String) -> UIImage? {
        return dispatcher.sync {
            if let image = cache.object(forKey: hash as NSString) {
                return image;
            }
            if let image = UIImage(contentsOfFile: avatarCacheUrl.appendingPathComponent(hash).path) {
                cache.setObject(image, forKey: hash as NSString);
                return image;
            }
            return nil;
        }
    }

    open func removeAvatar(for hash: String) {
        dispatcher.sync(flags: .barrier) {
            try? FileManager.default.removeItem(at: avatarCacheUrl.appendingPathComponent(hash));
            cache.removeObject(forKey: hash as NSString);
        }
    }
    
    open func storeAvatar(data: Data, for hash: String) {
        dispatcher.async(flags: .barrier) {
            if !FileManager.default.fileExists(atPath: self.avatarCacheUrl.path) {
                try? FileManager.default.createDirectory(at: self.avatarCacheUrl, withIntermediateDirectories: true, attributes: nil);
            }
            
            _ = FileManager.default.createFile(atPath: self.avatarCacheUrl.appendingPathComponent(hash).path, contents: data, attributes: nil);
        }
    }
            
    open func updateAvatar(hash: String?, type: AvatarType, for jid: BareJID, on account: BareJID, completionHandler: @escaping ()->Void) {
        dispatcher.async(flags: .barrier) {
            if let oldHash = self.avatarHash(for: jid, on: account)[type] {
                guard hash == nil || hash! != oldHash else {
                    return;
                }
                DispatchQueue.global(qos: .background).async {
                    self.removeAvatar(for: oldHash);
                }
                let params = ["account": account, "jid": jid, "type": type.rawValue] as [String : Any?];
                _ = try! self.deleteAvatarHashForJidStmt.update(params);
            }
            
            guard hash != nil else {
                return;
            }
        
            let params = ["account": account, "jid": jid, "type": type.rawValue, "hash": hash!] as [String : Any?];
            _ = try! self.insertAvatarHashForJidStmt.insert(params);
            
            DispatchQueue.global(qos: .background).async {
                completionHandler();
            }
        }
    }
    
    public func clearCache() {
        cache.removeAllObjects();
    }
}

public enum AvatarType: String {
    case vcardTemp
    case pepUserAvatar
    
    public static let ALL = [AvatarType.pepUserAvatar, AvatarType.vcardTemp];
}
