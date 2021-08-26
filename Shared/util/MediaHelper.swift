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

open class MediaHelper {
    
    public static func compressImage(url: URL, filename: String, quality: ImageQuality, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard quality != .original else {
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent);
            do {
                try  FileManager.default.copyItem(at: url, to: tempUrl);
            } catch {
                completionHandler(.failure(.noAccessError))
                return;
            }
            completionHandler(.success(tempUrl));
            return;
        }
        guard let inData = try? Data(contentsOf: url), let image = UIImage(data: inData) else {
            completionHandler(.failure(.notSupported));
            return;
        }
        compressImage(image: image, filename: filename, quality: quality, completionHandler: completionHandler);
    }
    
    public static func compressImage(image: UIImage, filename: String, quality: ImageQuality, completionHandler: @escaping(Result<URL,ShareError>)->Void) {
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename + ".jpg", isDirectory: false);
        guard let outData = image.scaled(maxWidthOrHeight: quality.size)?.jpegData(compressionQuality: quality.quality) else {
            return;
        }
        do {
            try outData.write(to: fileUrl);
            completionHandler(.success(fileUrl));
        } catch {
            completionHandler(.failure(.noAccessError));
            return;
        }
    }
    
    public static func compressMovie(url: URL, filename: String, quality: VideoQuality, progressCallback: @escaping (Float)->Void, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard quality != .original else {
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent);
            do {
                try FileManager.default.copyItem(at: url, to: tempUrl);
            } catch {
                completionHandler(.failure(.noAccessError))
                return;
            }
            completionHandler(.success(tempUrl));
            return;
        }
        let video = AVAsset(url: url);
        let exportSession = AVAssetExportSession(asset: video, presetName: quality.preset)!;
        exportSession.shouldOptimizeForNetworkUse = true;
        exportSession.outputFileType = .mp4;
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename + ".mp4", isDirectory: false);
        exportSession.outputURL = fileUrl;
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
            progressCallback(exportSession.progress);
        })
        exportSession.exportAsynchronously {
            timer.invalidate();
            completionHandler(.success(fileUrl));
        }
    }
    
}

public enum ShareError: Error {
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
            return "Server did not confirm file upload correctly."
        case .unknownError:
            return "Please try again later."
        case .noAccessError:
            return "It was not possible to access the file."
        case .noFileSizeError:
            return "Could not retrieve file size.";
        case .noMimeTypeError:
            return "Could not detect MIME type of a file.";
        case .notSupported:
            return "Feature not supported by XMPP server";
        case .fileTooBig:
            return "File is too big to share";
        case .httpError:
            return "Upload to HTTP server failed.";
        }
    }
}
