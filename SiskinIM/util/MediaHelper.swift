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

class MediaHelper {
    
    static func askImageQuality(controller: UIViewController, forceQualityQuestion askQuality: Bool, _ completionHandler: @escaping (Result<ImageQuality,ShareError>)->Void) {
        if let quality = askQuality ? nil : Settings.imageQuality {
            completionHandler(.success(quality));
        } else {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Select quality", message: nil, preferredStyle: .alert);
                
                let values: [ImageQuality] = [.original, .highest, .high, .medium, .low];
                for value in  values {
                    alert.addAction(UIAlertAction(title: value.rawValue.capitalized, style: .default, handler: { _ in
                        completionHandler(.success(value));
                    }));
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                    completionHandler(.failure(.noAccessError));
                }))
                controller.present(alert, animated: true);
            }
        }
    }
    
    static func askVideoQuality(controller: UIViewController, forceQualityQuestion askQuality: Bool, _ completionHandler: @escaping (Result<VideoQuality,ShareError>)->Void) {
        if let quality = askQuality ? nil : Settings.videoQuality {
            completionHandler(.success(quality));
        } else {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Select quality", message: nil, preferredStyle: .alert);
                
                let values: [VideoQuality] = [.original, .high, .medium, .low];
                for value in  values {
                    alert.addAction(UIAlertAction(title: value.rawValue.capitalized, style: .default, handler: { _ in
                        completionHandler(.success(value));
                    }));
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                    completionHandler(.failure(.noAccessError));
                }))
                controller.present(alert, animated: true);
            }
        }
    }
    
    static func compressImage(url: URL, filename: String, quality: ImageQuality, deleteSource: Bool, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard quality != .original else {
            completionHandler(.success(url));
            return;
        }
        guard let inData = try? Data(contentsOf: url), let image = UIImage(data: inData) else {
            if deleteSource {
                try? FileManager.default.removeItem(at: url);
            }
            completionHandler(.failure(.notSupported));
            return;
        }
        if deleteSource {
            try? FileManager.default.removeItem(at: url);
        }
        compressImage(image: image, filename: filename, quality: quality, completionHandler: completionHandler);
    }
    
    static func compressImage(image: UIImage, filename: String, quality: ImageQuality, completionHandler: @escaping(Result<URL,ShareError>)->Void) {
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
    
    static func compressMovie(url: URL, filename: String, quality: VideoQuality, deleteSource: Bool, progressCallback: @escaping (Float)->Void, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard quality != .original else {
            completionHandler(.success(url));
            return;
        }
        let video = AVAsset(url: url);
        print("asset:", video, video.isExportable, video.isPlayable)
        let exportSession = AVAssetExportSession(asset: video, presetName: quality.preset)!;
        print("export profiles:", AVAssetExportSession.exportPresets(compatibleWith: video));
        exportSession.shouldOptimizeForNetworkUse = true;
        exportSession.outputFileType = .mp4;
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename + ".mp4", isDirectory: false);
        exportSession.outputURL = fileUrl;
        print("exporting movie from:", url, "to:", fileUrl, FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: fileUrl.path));
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
            progressCallback(exportSession.progress);
        })
        exportSession.exportAsynchronously {
            timer.invalidate();
            print("export status:", exportSession.status, exportSession.error)
            if deleteSource {
                try? FileManager.default.removeItem(at: url);
            }
            completionHandler(.success(fileUrl));
        }
    }
    
}
