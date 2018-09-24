//
// ImageCache.swift
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
import MobileCoreServices

class ImageCache {

    public static let DISK_CACHE_IMAGE_REMOVED = Notification.Name("DISK_CACHE.IMAGE_REMOVED");
    
    static let shared = ImageCache();
    
    fileprivate let diskCacheUrl: URL = {
        let tmp = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("images", isDirectory: true);
        if !FileManager.default.fileExists(atPath: tmp.path) {
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: nil);
        }
        return tmp;
    }();

    
    fileprivate let cache: NSCache<NSString,ImageHolder> = {
        let tmp = NSCache<NSString,ImageHolder>();
        tmp.countLimit = 20;
        tmp.totalCostLimit = 20 * 1024 * 1024;
        return tmp;
    }();
    
    var diskCacheSize: Int {
        var size: Int = 0;
        try? FileManager.default.contentsOfDirectory(at: diskCacheUrl, includingPropertiesForKeys: [.fileAllocatedSizeKey], options: .skipsSubdirectoryDescendants).forEach { (url) in
            size = size + ((try? FileManager.default.attributesOfItem(atPath: url.path)[FileAttributeKey.size] as? Int) ?? 0)!;
        }
        return size;
    }
    
    func emptyDiskCache(olderThan: Date? = nil) {
        try? FileManager.default.contentsOfDirectory(at: diskCacheUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants).forEach({ (url) in
            if olderThan != nil {
                let creationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.creationDate] as? Date;
                if (creationDate == nil) || (creationDate!.compare(olderThan!) == .orderedDescending) {
                    return;
                }
            }
            try? FileManager.default.removeItem(at: url);
            cache.removeObject(forKey: url.pathComponents.last! as NSString);
            NotificationCenter.default.post(name: ImageCache.DISK_CACHE_IMAGE_REMOVED, object: self, userInfo: ["url": url]);
        });
    }
    
    func clearInMemoryCache() {
        cache.removeAllObjects();
    }
    
    func getURL(for key: String?) -> URL? {
        guard key != nil else {
            return nil;
        }
        
        return diskCacheUrl.appendingPathComponent(key!);
    }
    
    func get(for key: String?, ifMissing: (()->Void)?) -> UIImage? {
        guard key != nil else {
            ifMissing?();
            return nil;
        }
        let val = cache.object(forKey: key! as NSString);
        if val?.beginContentAccess() ?? false {
            defer {
                val?.endContentAccess();
            }
            return val!.image;
        }
        let image = UIImage(contentsOfFile: diskCacheUrl.appendingPathComponent(key!).path);
        if image == nil {
            ifMissing?();
        } else {
            cache.setObject(ImageHolder(image: image!), forKey: key! as NSString);
        }
        return image;
    }
    
    func set(image value: UIImage, completion: ((String)->Void)? = nil) {
        let key = "\(UUID().description).jpg";
        cache.setObject(ImageHolder(image: value), forKey: key as NSString);
        DispatchQueue.global(qos: .background).async {
            if let data = value.jpegData(compressionQuality: 1.0) {
                let newUrl = self.diskCacheUrl.appendingPathComponent(key);
                _ = FileManager.default.createFile(atPath: newUrl.path, contents: data, attributes: nil);
                completion?(key);
            }
        }
    }
    
    func set(url value: URL, mimeType: String? = nil, completion: ((String)->Void)? = nil) {
        let uti = mimeType != nil ? UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType! as CFString, kUTTypeImage)?.takeRetainedValue() : nil;
        let ext = uti != nil ? UTTypeCopyPreferredTagWithClass(uti! as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue() : nil;
        let key = ext == nil ? UUID().description : "\(UUID().description).\(ext!)";
        let newUrl = diskCacheUrl.appendingPathComponent(key);
        try? FileManager.default.copyItem(at: value, to: newUrl);
        DispatchQueue.global(qos: .background).async {
            if let image = UIImage(contentsOfFile: newUrl.path) {
                self.cache.setObject(ImageHolder(image: image), forKey: key as NSString);
                completion?(key);
            } else {
                print("no image from copied URL", value, newUrl);
            }
        }
    }
 
    fileprivate class ImageHolder: NSDiscardableContent {
        
        var counter = 0;
        var image: UIImage!;
        
        fileprivate init?(data: NSData?) {
            guard data != nil else {
                return nil;
            }
            
            image = UIImage(data: data! as Data);
            guard image != nil else {
                return nil;
            }
        }
        
        fileprivate init(image: UIImage) {
            self.image = image;
        }
        
        @objc fileprivate func discardContentIfPossible() {
            if counter == 0 {
                image = nil;
            }
        }
        
        @objc fileprivate func isContentDiscarded() -> Bool {
            return image == nil;
        }
        
        @objc fileprivate func beginContentAccess() -> Bool {
            guard !isContentDiscarded() else {
                return false;
            }
            counter += 1;
            return true;
        }
        
        @objc fileprivate func endContentAccess() {
            counter -= 1;
        }
    }

}
