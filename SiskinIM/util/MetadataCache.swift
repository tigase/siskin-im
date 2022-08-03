//
// MetadataCache.swift
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
import LinkPresentation
import Martin

class MetadataCache {

    static let instance = MetadataCache();

    private var cache: [URL: Result<LPLinkMetadata, MetadataCache.CacheError>] = [:];
    private let diskCacheUrl: URL;
    private let dispatcher = QueueDispatcher(label: "MetadataCache");

    private var inProgress: [URL: OperationQueue] = [:];
    
    var size: Int {
        guard let enumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(at: diskCacheUrl, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else {
            return 0;
        }

        return enumerator.map({ $0 as! URL}).filter({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false}).map({ (try? $0.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0}).reduce(0, +);
    }
    
    init() {
        diskCacheUrl = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("metadata", isDirectory: true);
        if !FileManager.default.fileExists(atPath: diskCacheUrl.path) {
            try! FileManager.default.createDirectory(at: diskCacheUrl, withIntermediateDirectories: true, attributes: nil);
        }
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
    }
    
    @objc func messageRemoved(_ notification: Notification) {
        guard let item = notification.object as? ConversationEntry, case .deleted = item.payload else {
            return;
        }
        removeMetadata(for: "\(item.id)");
    }

    func store(_ value: LPLinkMetadata, for id: String) {
        let fileUrl = diskCacheUrl.appendingPathComponent("\(id).metadata");
        guard let codedData = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false) else {
            return;
        }

        try? codedData.write(to: fileUrl);
    }

    func metadata(for id: String) -> LPLinkMetadata? {
        guard let data = FileManager.default.contents(atPath: diskCacheUrl.appendingPathComponent("\(id).metadata").path) else {
            return nil;
        }

        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data);
    }
    
    func removeMetadata(for id: String) {
        try? FileManager.default.removeItem(at: diskCacheUrl.appendingPathComponent("\(id).metadata"));
    }

    
    func clear(olderThan: Date? = nil) {
        guard let messageDirs = try? FileManager.default.contentsOfDirectory(at: diskCacheUrl, includingPropertiesForKeys: [.creationDateKey], options: .skipsSubdirectoryDescendants) else {
            return;
        }
        for dir in messageDirs {
            if olderThan == nil || (((try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) < olderThan!) {
                do {
                    try FileManager.default.removeItem(at: dir);
                } catch {}
            }
        }
    }
    
    func generateMetadata(for url: URL, withId id: String, completionHandler: @escaping (LPLinkMetadata?)->Void) {
        dispatcher.async {
            if let queue = self.inProgress[url] {
                queue.addOperation {
                    completionHandler(self.metadata(for: id));
                }
            } else {
                let queue = OperationQueue();
                queue.isSuspended = true;
                self.inProgress[url] = queue;
                
                queue.addOperation {
                    completionHandler(self.metadata(for: id));
                }
                
                DispatchQueue.main.async {
                    let provider = LPMetadataProvider();
                    provider.startFetchingMetadata(for: url, completionHandler: { (meta, error) in
                        if let metadata = meta {
                            self.store(metadata, for: id);
                        } else {
                            let metadata = LPLinkMetadata();
                            metadata.originalURL = url;
                            self.store(metadata, for: id);
                        }
                        self.dispatcher.async {
                            self.inProgress.removeValue(forKey: url);
                            queue.isSuspended = false;
                        }
                    })
                }
            }
        }
    }

    enum CacheError: Error {
        case NO_DATA
        case RETRIEVAL_ERROR
    }
}

