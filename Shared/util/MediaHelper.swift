//
// MediaHelper.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import AVKit

public struct ShareFileInfo {
    
    public let filename: String;
    public let suffix: String?;
    
    public var filenameWithSuffix: String {
        if let suffix = suffix {
            return "\(filename).\(suffix)";
        } else {
            return filename;
        }
    }
    
    public init(filename: String, suffix: String?) {
        self.filename = filename;
        if suffix?.isEmpty ?? true {
            self.suffix = nil;
        } else {
            self.suffix = suffix;
        }
    }
    
    public func with(suffix: String?) -> ShareFileInfo {
        return .init(filename: filename, suffix: suffix);
    }
    
    public func with(filename: String) -> String {
        if let suffix = self.suffix {
            return "\(filename).\(suffix)";
        }
        return filename;
    }
    
    public static func from(url: URL, defaultSuffix: String?) -> ShareFileInfo {
        let name = url.lastPathComponent;
        var startOffset = name.startIndex;
        if name.hasPrefix("trim.") {
            startOffset = name.index(startOffset, offsetBy: "trim.".count);
        }
        
        if let idx = name.lastIndex(of: "."), idx > startOffset {
            return ShareFileInfo(filename: String(name[startOffset..<idx]), suffix: String(name[name.index(after: idx)..<name.endIndex]));
        } else {
            return ShareFileInfo(filename: String(name[startOffset..<name.endIndex]), suffix: defaultSuffix);
        }
    }
}

open class MediaHelper {
    
    public static func compressImage(url: URL, fileInfo: ShareFileInfo, quality: ImageQuality, completionHandler: @escaping (Result<(URL,ShareFileInfo),ShareError>)->Void) {
        guard quality != .original else {
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileInfo.with(filename: UUID().uuidString));
            do {
                try  FileManager.default.copyItem(at: url, to: tempUrl);
            } catch {
                completionHandler(.failure(.noAccessError))
                return;
            }
            completionHandler(.success((tempUrl, fileInfo)));
            return;
        }
        guard let inData = try? Data(contentsOf: url), let image = UIImage(data: inData) else {
            completionHandler(.failure(.notSupported));
            return;
        }
        compressImage(image: image, fileInfo: fileInfo, quality: quality, completionHandler: completionHandler);
    }
    
    public static func compressImage(image: UIImage, fileInfo: ShareFileInfo, quality: ImageQuality, completionHandler: @escaping(Result<(URL,ShareFileInfo),ShareError>)->Void) {
        let newFileInfo = fileInfo.with(suffix: "jpg");
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(newFileInfo.filenameWithSuffix, isDirectory: false);
        guard let outData = image.scaled(maxWidthOrHeight: quality.size)?.jpegData(compressionQuality: quality.quality) else {
            return;
        }
        do {
            try outData.write(to: fileUrl);
            completionHandler(.success((fileUrl,newFileInfo)));
        } catch {
            completionHandler(.failure(.noAccessError));
            return;
        }
    }
    
    public static func compressMovie(url: URL, fileInfo: ShareFileInfo, quality: VideoQuality, progressCallback: @escaping (Float)->Void, completionHandler: @escaping (Result<(URL,ShareFileInfo),Error>)->Void) {
        guard quality != .original else {
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileInfo.with(filename: UUID().uuidString));
            do {
                try FileManager.default.copyItem(at: url, to: tempUrl);
            } catch {
                completionHandler(.failure(ShareError.noAccessError))
                return;
            }
            completionHandler(.success((tempUrl,fileInfo)));
            return;
        }
        let video = AVAsset(url: url);
        let exportSession = AVAssetExportSession(asset: video, presetName: quality.preset)!;
        exportSession.shouldOptimizeForNetworkUse = true;
        exportSession.outputFileType = .mp4;
        let newFileInfo = fileInfo.with(suffix: "mp4");
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(newFileInfo.filenameWithSuffix, isDirectory: false);
        exportSession.outputURL = fileUrl;
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
            progressCallback(exportSession.progress);
        })
        exportSession.exportAsynchronously {
            timer.invalidate();
            if let error = exportSession.error {
                completionHandler(.failure(error));
            } else {
                completionHandler(.success((fileUrl,newFileInfo)));
            }
        }
    }
    
}

public enum ShareError: Error, LocalizedError {
    case unknownError
    case noAccessError
    case noFileSizeError
    case noMimeTypeError
    
    case notSupported
    case fileTooBig
    
    case httpError
    case invalidResponseCode(url: URL)
    
    public var message: String {
        switch self {
        case .invalidResponseCode:
            return NSLocalizedString("Server did not confirm file upload correctly.", comment: "sharing error")
        case .unknownError:
            return NSLocalizedString("Please try again later.", comment: "sharing error")
        case .noAccessError:
            return NSLocalizedString("It was not possible to access the file.", comment: "sharing error")
        case .noFileSizeError:
            return NSLocalizedString("Could not retrieve file size.", comment: "sharing error")
        case .noMimeTypeError:
            return NSLocalizedString("Could not detect MIME type of a file.", comment: "sharing error")
        case .notSupported:
            return NSLocalizedString("Feature not supported by XMPP server", comment: "sharing error")
        case .fileTooBig:
            return NSLocalizedString("File is too big to share", comment: "sharing error")
        case .httpError:
            return NSLocalizedString("Upload to HTTP server failed.", comment: "sharing error")
        }
    }
}
