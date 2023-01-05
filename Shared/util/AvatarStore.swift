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
import Martin
import TigaseSQLite3

extension Query {
    static let avatarFindHash = Query("SELECT type, hash FROM avatars_cache WHERE account = :account AND jid = :jid");
    static let avatarDeleteHash = Query("DELETE FROM avatars_cache WHERE jid = :jid AND account = :account AND (:type IS NULL OR type = :type)");
    static let avatarInsertHash = Query("INSERT INTO avatars_cache (jid, account, hash, type) VALUES (:jid,:account,:hash,:type)");
}


open class AvatarStore {
    
    private let cacheDirectory: URL;
    
    private let cache = NSCache<NSString,UIImage>();

    public init() {
        cacheDirectory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("Library", isDirectory: true).appendingPathComponent("Caches", isDirectory: true).appendingPathComponent("avatars", isDirectory: true);

        let oldCacheDirectory = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("avatars", isDirectory: true);

        if FileManager.default.fileExists(atPath: oldCacheDirectory.path) {
            if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
                let parentDir = cacheDirectory.deletingLastPathComponent();
                
                // we need to create parent directory if it does not exist
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try! FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil);
                }
                // we need to move cache
                try! FileManager.default.moveItem(at: oldCacheDirectory, to: cacheDirectory);
            }
        } else {
            // nothing to move, let's check if destinatin exists
            if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil);
            }
        }
    }
    
    open func hasAvatar(forHash hash: String) -> Bool {
        return FileManager.default.fileExists(atPath: self.cacheDirectory.appendingPathComponent(hash).path);
    }
        
    open func avatarHash(for jid: BareJID, on account: BareJID) -> [AvatarHash] {
        return try! Database.main.reader({ database in
            try database.select(query: .avatarFindHash, params: ["account": account, "jid": jid]).mapAll({ cursor -> AvatarHash? in
                guard let type = AvatarType(rawValue: cursor["type"]!), let hash: String = cursor["hash"] else {
                    return nil;
                }
                return AvatarHash(type: type, hash: hash);
            });
        });
    }
    
    open func avatar(for hash: String) -> UIImage? {
        if let image = cache.object(forKey: hash as NSString) {
            return image;
        }
        
        if let image = UIImage(contentsOfFile: self.cacheDirectory.appendingPathComponent(hash).path) {
            cache.setObject(image, forKey: hash as NSString);
            return image;
        }
                            
        return nil;
    }
    
    open func removeAvatar(for hash: String) {
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(hash));
        cache.removeObject(forKey: hash as NSString);
    }
    
    open func storeAvatar(data: Data, for hash: String) {
        if !FileManager.default.fileExists(atPath: self.cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true, attributes: nil);
        }
            
        _ = FileManager.default.createFile(atPath: self.cacheDirectory.appendingPathComponent(hash).path, contents: data, attributes: nil);
    }
            
    public enum AvatarUpdateResult {
        case newAvatar(String)
        case notChanged
        case noAvatar
    }
    
    open func removeAvatarHash(for jid: BareJID, on account: BareJID, type: AvatarType) {
        try! Database.main.writer({ database in
            try database.delete(query: .avatarDeleteHash, params: ["account": account, "jid": jid, "type": type.rawValue]);
        });
    }
    
    open func updateAvatarHash(for jid: BareJID, on account: BareJID, hash: AvatarHash) -> Bool {
        let oldHashes = avatarHash(for: jid, on: account);
        guard !oldHashes.contains(hash) else {
            return false;
        }
            
        try! Database.main.writer({ database in
            try database.delete(query: .avatarDeleteHash, params: ["account": account, "jid": jid, "type": hash.type.rawValue]);
            try database.insert(query: .avatarInsertHash, params: ["account": account, "jid": jid, "type": hash.type.rawValue, "hash": hash.hash]);
        })
        
        return true;
    }
 
    public func clearCache() {
        cache.removeAllObjects();
    }
}

public struct AvatarHash: Comparable, Equatable {
    
    public static func < (lhs: AvatarHash, rhs: AvatarHash) -> Bool {
        return lhs.type < rhs.type;
    }
    
    
    public let type: AvatarType;
    public let hash: String;
    
    public init(type: AvatarType, hash: String) {
        self.type = type
        self.hash = hash
    }
}

public enum AvatarType: String, Comparable {
    public static func < (lhs: AvatarType, rhs: AvatarType) -> Bool {
        return lhs.value < rhs.value;
    }
    
    case vcardTemp
    case pepUserAvatar
    
    private var value: Int {
        switch self {
        case .vcardTemp:
            return 2;
        case .pepUserAvatar:
            return 1;
        }
    }
    
    public static let ALL: [AvatarType] = [.pepUserAvatar, .vcardTemp];
}
