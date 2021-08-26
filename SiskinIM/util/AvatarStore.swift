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
import Shared
import TigaseSwift
import TigaseSQLite3

extension Query {
    static let avatarFindHash = Query("SELECT type, hash FROM avatars_cache WHERE account = :account AND jid = :jid");
    static let avatarDeleteHash = Query("DELETE FROM avatars_cache WHERE jid = :jid AND account = :account AND (:type IS NULL OR type = :type)");
    static let avatarInsertHash = Query("INSERT INTO avatars_cache (jid, account, hash, type) VALUES (:jid,:account,:hash,:type)");
}


open class AvatarStore {
    
    fileprivate let dispatcher = QueueDispatcher(label: "avatar_store", attributes: .concurrent);
    fileprivate let cacheDirectory: URL;
    
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
                
        print("avatars cache directory:", cacheDirectory.path);
    }
    
    open func hasAvatarFor(hash: String) -> Bool {
        return dispatcher.sync {
            return FileManager.default.fileExists(atPath: self.cacheDirectory.appendingPathComponent(hash).path);
        }
    }
    
    open func avatarHash(for jid: BareJID, on account: BareJID) -> [AvatarHash] {
        return dispatcher.sync {
            return try! Database.main.reader({ database in
                try database.select(query: .avatarFindHash, params: ["account": account, "jid": jid]).mapAll({ cursor -> AvatarHash? in
                    guard let type = AvatarType(rawValue: cursor["type"]!), let hash: String = cursor["hash"] else {
                        return nil;
                    }
                    return AvatarHash(type: type, hash: hash);
                });
            });
        }
    }
    
    open func avatar(for hash: String) -> UIImage? {
        return dispatcher.sync {
            if let image = cache.object(forKey: hash as NSString) {
                return image;
            }
            if let image = UIImage(contentsOfFile: cacheDirectory.appendingPathComponent(hash).path) {
                cache.setObject(image, forKey: hash as NSString);
                return image;
            }
            return nil;
        }
    }

    func avatar(for hash: String, completionHandler: @escaping (Result<UIImage,ErrorCondition>)->Void) {
        dispatcher.async {
            if let image = self.cache.object(forKey: hash as NSString) {
                completionHandler(.success(image));
                return;
            }
            if let image = UIImage(contentsOfFile: self.cacheDirectory.appendingPathComponent(hash).path) {
                self.cache.setObject(image, forKey: hash as NSString);
                completionHandler(.success(image));
                return;
            }
            completionHandler(.failure(.conflict))
        }
    }
    
    open func removeAvatar(for hash: String) {
        dispatcher.sync(flags: .barrier) {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(hash));
            cache.removeObject(forKey: hash as NSString);
        }
    }
    
    open func storeAvatar(data: Data, for hash: String) {
        dispatcher.async(flags: .barrier) {
            if !FileManager.default.fileExists(atPath: self.cacheDirectory.path) {
                try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true, attributes: nil);
            }
            
            _ = FileManager.default.createFile(atPath: self.cacheDirectory.appendingPathComponent(hash).path, contents: data, attributes: nil);
        }
    }
            
    public enum AvatarUpdateResult {
        case newAvatar(String)
        case notChanged
        case noAvatar
    }
    
    open func removeAvatarHash(for jid: BareJID, on account: BareJID, type: AvatarType, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.delete(query: .avatarDeleteHash, params: ["account": account, "jid": jid, "type": type.rawValue]);
            });
            completionHandler();
        }
    }
    
    open func updateAvatarHash(for jid: BareJID, on account: BareJID, hash: AvatarHash, completionHandler: @escaping (AvatarUpdateResult)->Void ) {
        dispatcher.async(flags: .barrier) {
            let oldHashes = self.avatarHash(for: jid, on: account);
            guard !oldHashes.contains(hash) else {
                completionHandler(.notChanged);
                return;
            }
            
            try! Database.main.writer({ database in
                try database.delete(query: .avatarDeleteHash, params: ["account": account, "jid": jid, "type": hash.type.rawValue]);
                try database.insert(query: .avatarInsertHash, params: ["account": account, "jid": jid, "type": hash.type.rawValue, "hash": hash.hash]);
            })

            if oldHashes.isEmpty {
                completionHandler(.newAvatar(hash.hash));
            } else if let first = oldHashes.first, first >= hash {
                completionHandler(.newAvatar(hash.hash));
            } else {
                completionHandler(.notChanged);
            }
        }
    }
 
    public func clearCache() {
        cache.removeAllObjects();
    }
}

public struct AvatarHash: Comparable, Equatable {
    
    public static func < (lhs: AvatarHash, rhs: AvatarHash) -> Bool {
        return lhs.type < rhs.type;
    }
    
    
    let type: AvatarType;
    let hash: String;
    
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
