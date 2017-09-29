//
// BaseChatViewController_PreviewExtension.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

protocol BaseChatViewController_PreviewExtension {

    var xmppService: XmppService! { get }
    
    func updateItem(msgId: Int, handler: @escaping (BaseChatViewController_PreviewExtension_PreviewAwareItem)->Void);
    
}

protocol BaseChatViewController_PreviewExtension_PreviewAwareItem: class {

    var preview: String? { get set }
    
}

extension BaseChatViewController_PreviewExtension {
    
    func downloadPreview(url: URL, msgId: Int) {
        guard Settings.MaxImagePreviewSize.getInt() != 0 else {
            return;
        }
        
        getHeaders(url: url) { (mimeType, size, errCode) in
            if mimeType?.hasPrefix("image/") ?? false && (size ?? Int64.max) < self.getImageDownloadSizeLimit() {
                self.downloadImageFile(url: url, completion: { (key) in
                    let previewKey = key == nil ? nil : "preview:image:\(key!)";
                    self.xmppService.dbChatHistoryStore.updatePreview(msgId: msgId, preview: previewKey ?? "", completion: { (msgId) in
                        if key != nil {
                            self.updateItem(msgId: msgId, handler: { (item) in
                                item.preview = previewKey;
                            })
                        }
                        print("preview downloaded and updated to", key, "for msgId", msgId);
                    })
                })
            } else {
                self.xmppService.dbChatHistoryStore.updatePreview(msgId: msgId, preview: "", completion: nil);
            }
        }
    }
 
    func getHeaders(url: URL, completion: @escaping (String?, Int64?, Int)->Void) {
        var request = URLRequest(url: url);
        request.httpMethod = "HEAD";
        URLSession.shared.dataTask(with: request) { (data, resp, error) in
            let response = resp as? HTTPURLResponse;
            print("got mime type =", response?.mimeType, "with size", response?.expectedContentLength, "at", url);

            completion(response?.mimeType, response?.expectedContentLength, response?.statusCode ?? 500);
            }.resume();
    }

    fileprivate func downloadImageFile(url: URL, completion: @escaping (String?)->Void) {
        URLSession.shared.downloadTask(with: url, completionHandler: { (tmpUrl, resp, error) in
            print("downloaded content of", url, "to", tmpUrl, "response:", resp, "error:", error);
            guard let response = resp as? HTTPURLResponse else {
                completion(nil);
                return;
            }
            guard tmpUrl != nil && error == nil else {
                completion(nil);
                return;
            }
            
            if let image = UIImage(contentsOfFile: tmpUrl!.path) {
                print("loaded image", url, "size", image.size);
                ImageCache.shared.set(url: tmpUrl!, mimeType: response.mimeType) { (key) in
                    completion(key);
                }
            } else {
                completion(nil);
            }
        }).resume();
    }
    
    func getImageDownloadSizeLimit() -> Int64 {
        let val = Settings.MaxImagePreviewSize.getInt();
        if val > (Int.max / (1024*1024)) {
            return Int64(val);
        } else {
            return Int64(val * 1024 * 1024);
        }
    }
}
