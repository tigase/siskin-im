//
// BaseChatViewController+ShareMedia.swift
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
import PhotosUI
import Shared

extension ChatViewInputBar {
        
    class LongPressShareButton: ShareButton {
        
        @objc func longPress(gesture: UILongPressGestureRecognizer) {
            
        }
        
        override func setup() {
            super.setup();
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(longPress(gesture:)));
            gesture.minimumPressDuration = 1.0;
            self.addGestureRecognizer(gesture);
        }
        
    }
    
    class ShareImageButton: LongPressShareButton {
        
        override func execute(_ sender: Any) {
            if #available(iOS 14.0, *) {
                controller?.selectPhotoFromLibrary();
            } else {
                controller?.selectPhoto(.photoLibrary)
            }
        }
        
        override func longPress(gesture: UILongPressGestureRecognizer) {
            controller?.askMediaQuality = true;
            if #available(iOS 14.0, *) {
                controller?.selectPhotoFromLibrary();
            } else {
                controller?.selectPhoto(.photoLibrary)
            }
        }
        
        override func setup() {
            super.setup();
            let image = UIImage(systemName: "photo");
            setImage(image, for: .normal);
        }
    }
    
    class ShareCameraImageButton: LongPressShareButton {
        
        override func execute(_ sender: Any) {
            controller?.selectPhoto(.camera)
        }
        
        override func longPress(gesture: UILongPressGestureRecognizer) {
            controller?.askMediaQuality = true;
            controller?.selectPhoto(.camera);
        }
        
        override func setup() {
            super.setup();
            let image = UIImage(systemName: "camera");
            setImage(image, for: .normal);
        }
    }

}


@available(iOS 14.0, *)
extension BaseChatViewController: PHPickerViewControllerDelegate {
        
    func selectPhotoFromLibrary() {
        var config = PHPickerConfiguration();
        config.selectionLimit = 1;
        config.filter = .any(of: [.videos, .images]);
        config.preferredAssetRepresentationMode = .current;
                
        let picker = PHPickerViewController(configuration: config);
        picker.delegate = self;
        
        present(picker, animated: true);
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true);
        
        if let provider = results.first?.itemProvider {
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadFileRepresentation(forTypeIdentifier: "public.image", completionHandler: self.handleLoaded(imageUrl:error:));
            } else if provider.hasItemConformingToTypeIdentifier("public.movie") {
                provider.loadFileRepresentation(forTypeIdentifier: "public.movie", completionHandler: self.handleLoaded(movieUrl:error:));
            } else {
                showAlert(shareError: .noAccessError);
            }
        }
    }
    
    private func handleLoaded(imageUrl url: URL?, error: Error?) {
        guard let url = url, error == nil else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .noAccessError);
            }
            return;
        }

        guard let localUrl = copyFileLocally(url: url) else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .unknownError);
            }
            return;
        }

        Task {
            do {
                try await upload(imageUrl: localUrl, fileInfo: ShareFileInfo.from(url: url, defaultSuffix: "jpg"));
            } catch ShareError.cancelled {
            } catch {
                self.showAlert(error: error);
            }
        }
    }
    
    private func handleLoaded(movieUrl url: URL?, error: Error?) {
        guard let url = url, error == nil else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .noAccessError);
            }
            return;
        }
        
        guard let localUrl = copyFileLocally(url: url) else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .unknownError);
            }
            return;
        }

        Task {
            do {
                try await upload(movieUrl: localUrl, fileInfo: ShareFileInfo.from(url: url, defaultSuffix: "mov"));
            } catch ShareError.cancelled {
            } catch {
                self.showAlert(error: error);
            }
        }
    }
    
}

extension BaseChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            
    func selectPhoto(_ source: UIImagePickerController.SourceType) {
        guard checkIfEnabledOrAsk(completionHandler: { [weak self] in self?.selectPhoto(source); }) else {
            return;
        }
        let picker = UIImagePickerController();
        picker.delegate = self;
        picker.allowsEditing = false;//true;
        picker.sourceType = source;
        picker.mediaTypes = ["public.image", "public.movie"];
        present(picker, animated: true, completion: nil);
    }
    
    @objc func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil);
    }
    
    @objc func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        Task {
            do {
                if let movieUrl = info[.mediaURL] as? URL {
                    defer {
                        try? FileManager.default.removeItem(at: movieUrl);
                    }
                    try await upload(movieUrl: movieUrl, fileInfo: ShareFileInfo.from(url: movieUrl, defaultSuffix: "mov"));
                } else if let imageUrl = info[.imageURL] as? URL {
                    defer {
                        try? FileManager.default.removeItem(at: imageUrl);
                    }
                    try await upload(imageUrl: imageUrl, fileInfo: ShareFileInfo.from(url: imageUrl, defaultSuffix: "jpg"));
                } else if let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
                    let quality = try await MediaHelper.askImageQuality(controller: self, forceQualityQuestion: self.askMediaQuality);
                    let (fileUrl, fileInfo) = try MediaHelper.compressImage(image: image, fileInfo: ShareFileInfo(filename: UUID().uuidString, suffix: "jpg"), quality: quality);
                    
                    defer {
                        try? FileManager.default.removeItem(at: fileUrl);
                    }

                    try await uploadFile(url: fileUrl, filename: fileInfo.filenameWithSuffix);
                }
            } catch ShareError.cancelled {
                // operation cancelled by the user - nothing to do
            } catch {
                self.showAlert(error: error);
            }
        }
        
        picker.dismiss(animated: true, completion: nil);
    }
    
    func upload(imageUrl url: URL, fileInfo: ShareFileInfo) async throws {
        let quality = try await MediaHelper.askImageQuality(controller: self, forceQualityQuestion: self.askMediaQuality);
        let (fileUrl, fileInfo) = try MediaHelper.compressImage(url: url, fileInfo: ShareFileInfo(filename: UUID().uuidString, suffix: "jpg"), quality: quality);
        
        defer {
            try? FileManager.default.removeItem(at: fileUrl);
        }
        
        try await uploadFile(url: fileUrl, filename: fileInfo.filenameWithSuffix);
    }
    
    func upload(movieUrl url: URL, fileInfo: ShareFileInfo) async throws {
        let quality = try await MediaHelper.askVideoQuality(controller: self, forceQualityQuestion: self.askMediaQuality);
        DispatchQueue.main.async {
            self.showProgressBar();
        }

        defer {
            DispatchQueue.main.async {
                self.hideProgressBar();
            }
        }
        
        let progressBar = self.progressBar;
        let (fileUrl,fileInfo) = try await MediaHelper.compressMovie(url: url, fileInfo: fileInfo, quality: quality, progressCallback: { progress in
            DispatchQueue.main.async {
               progressBar?.progress = progress;
            }
        });
        
        defer {
            try? FileManager.default.removeItem(at: fileUrl);
        }
        
        try await uploadFile(url: fileUrl, filename: fileInfo.filenameWithSuffix);
    }
        
    private func copyFileLocally(url: URL) -> URL? {
        let filename = url.lastPathComponent;
        var suffix: String = "";
        if let idx = filename.lastIndex(of: ".") {
            suffix = String(filename.suffix(from: idx));
        }
        
        let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + suffix, isDirectory: false);
        do {
            try FileManager.default.copyItem(at: url, to: tmpUrl);
        } catch {
            return nil;
        }
        return tmpUrl;
    }
        
    private func uploadFile(url fileUrl: URL, filename: String) async throws {
        let uploaded = try await self.share(filename: filename, url: fileUrl);

        var appendix = ChatAttachmentAppendix()
        appendix.filename = filename;
        appendix.filesize = uploaded.filesize;
        appendix.mimetype = uploaded.mimeType;
        appendix.state = .downloaded;

        try await self.sendAttachment(originalUrl: fileUrl, uploadedUrl: uploaded.url.absoluteString, appendix: appendix);
    }
    
}
