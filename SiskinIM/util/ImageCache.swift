//
// ImageCache.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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
import MobileCoreServices

class ImageCache {

    static func convertToAttachments() {
        // converting ImageCache!!!
        let diskCacheUrl = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("images", isDirectory: true);
        guard FileManager.default.fileExists(atPath: diskCacheUrl.path) else {
            return;
        }

        let previewsToConvert = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE preview IS NOT NULL").query(map: { cursor -> Int in
            return cursor["id"]!;
        });
        let convertStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, account, jid, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, preview, stanza_id FROM chat_history WHERE id = ?");
        let removePreviewStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET preview = NULL WHERE id = ?");

        let group = DispatchGroup();
        group.enter();

        previewsToConvert.forEach { id in
            guard let (item, preview, stanzaId) = try! convertStmt.findFirst(id, map: { (cursor) -> (ChatMessage, String, String?)? in
                let account: BareJID = cursor["account"]!;
                let jid: BareJID = cursor["jid"]!;
                let stanzaId: String? = cursor["stanza_id"];
                guard let item = DBChatHistoryStore.instance.itemFrom(cursor: cursor, for: account, with: jid) as? ChatMessage, let preview: String = cursor["preview"] else {
                    return nil;
                }
                return (item, preview, stanzaId);
            }) else {
                return;
            }

            if preview.hasPrefix("preview:image:"), item.error != nil {
                let url = diskCacheUrl.appendingPathComponent(String(preview.dropFirst(14)));
                if FileManager.default.fileExists(atPath: url.path) {
                    group.enter();
                    var appendix = ChatAttachmentAppendix();
                    var filename = "image.jpg";
                    if let values = try? url.resourceValues(forKeys: [.typeIdentifierKey, .fileSizeKey]) {
                        if let uti = values.typeIdentifier {
                            appendix.mimetype = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)?.takeRetainedValue() as String?;
                            if let ext = UTTypeCopyPreferredTagWithClass(kUTTagClassFilenameExtension, uti as CFString)?.takeRetainedValue() as String? {
                                filename = "image.\(ext)";
                            }
                        }
                        appendix.filesize = values.fileSize;
                    }
                    appendix.filename = filename;

                    let isAttachmentOnly = URL(string: item.message) != nil;

                    DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, type: .attachment, timestamp: item.timestamp, stanzaId: stanzaId, data: item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, chatAttachmentAppendix: appendix, skipItemAlreadyExists: true, completionHandler: { newId in
                        DownloadStore.instance.store(url, filename: filename, with: "\(newId)");
                        if isAttachmentOnly {
                            DBChatHistoryStore.instance.remove(item: item);
                        } else {
                            try! removePreviewStmt.update(item.id);
                        }
                        try? FileManager.default.removeItem(at: url);
                        group.leave();
                    });
                } else {
                    try! removePreviewStmt.update(item.id);
                }
            } else {
                try! removePreviewStmt.update(item.id);
            }
        }
        group.notify(queue: DispatchQueue.main, execute: {
            try? FileManager.default.removeItem(at: diskCacheUrl);
        })

        group.leave();

    }

}
