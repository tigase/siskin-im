//
// DownloadStore.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import UIKit
import Martin

class DownloadStore {
    
    static let instance = DownloadStore();

    fileprivate let queue = DispatchQueue(label: "download_store_queue");

    let diskCacheUrl: URL;
    
    //let cache = NSCache<NSString, NSImage>();
    var size: Int {
        guard let enumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(at: diskCacheUrl, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else {
            return 0;
        }

        return enumerator.map({ $0 as! URL}).filter({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false}).map({ (try? $0.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0}).reduce(0, +);
//        for enu
//        return (.map { url -> Int in
//            return (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0;
//            }.reduce(0, +)) ?? 0;
    }
    
    init() {
        diskCacheUrl = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("download", isDirectory: true);
        if !FileManager.default.fileExists(atPath: diskCacheUrl.path) {
            try! FileManager.default.createDirectory(at: diskCacheUrl, withIntermediateDirectories: true, attributes: nil);
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved(_:)), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
    }
    
    @objc func messageRemoved(_ notification: Notification) {
        guard let item = notification.object as? ConversationEntry else {
            return;
        }
        self.deleteFile(for: "\(item.id)")
    }
    
    func clear(olderThan: Date? = nil) {
        guard let messageDirs = try? FileManager.default.contentsOfDirectory(at: diskCacheUrl, includingPropertiesForKeys: [.creationDateKey], options: .skipsSubdirectoryDescendants) else {
            return;
        }
        for dir in messageDirs {
            if olderThan == nil || (((try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) < olderThan!), let id = Int(dir.lastPathComponent) {
                do {
                    try FileManager.default.removeItem(at: dir);
                    DBChatHistoryStore.instance.updateItem(id: id, updateAppendix: { appendix in
                        appendix.state = .removed;
                    });
                } catch {}
            }
        }
    }
    
    func store(_ source: URL, filename: String, with id: String) -> URL {
        let fileDir = diskCacheUrl.appendingPathComponent(id, isDirectory: true);
        if !FileManager.default.fileExists(atPath: fileDir.path) {
            try! FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true, attributes: nil);
        }
        
        try? FileManager.default.copyItem(at: source, to: fileDir.appendingPathComponent(filename));
        if !FileManager.default.fileExists(atPath: fileDir.appendingPathComponent(id).path) {
            try! FileManager.default.createSymbolicLink(at: fileDir.appendingPathComponent(id), withDestinationURL: fileDir.appendingPathComponent(filename));
        }
        
        return fileDir.appendingPathComponent(filename);
    }
    
    func url(for id: String) -> URL? {
        let linkUrl = diskCacheUrl.appendingPathComponent(id, isDirectory: true).appendingPathComponent(id);
        
        guard let filePath = try? FileManager.default.destinationOfSymbolicLink(atPath: linkUrl.path) else {
            return nil;
        }
        
        let filename = URL(fileURLWithPath: filePath).lastPathComponent;
        
        return diskCacheUrl.appendingPathComponent(id, isDirectory: true).appendingPathComponent(filename);
    }
            
    func deleteFile(for id: String) {
        let fileDir = diskCacheUrl.appendingPathComponent(id, isDirectory: true);
        guard FileManager.default.fileExists(atPath: fileDir.path) else {
            return;
        }
        try? FileManager.default.removeItem(at: fileDir);
        MetadataCache.instance.removeMetadata(for: id);
    }
    
}
