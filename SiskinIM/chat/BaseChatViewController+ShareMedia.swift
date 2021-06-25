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
                showAlert(shareError: .notSupported);
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

        guard let (localUrl, filename, _) = copyFileLocally(url: url, defaultSuffix: "jpg") else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .unknownError);
            }
            return;
        }

        upload(imageUrl: localUrl, filename: filename);
    }
    
    private func handleLoaded(movieUrl url: URL?, error: Error?) {
        guard let url = url, error == nil else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .noAccessError);
            }
            return;
        }
        
        guard let (localUrl, filename, _) = copyFileLocally(url: url, defaultSuffix: "mov") else {
            DispatchQueue.main.async {
                self.showAlert(shareError: .unknownError);
            }
            return;
        }

        upload(movieUrl: localUrl, filename: filename);
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
        if let movieUrl = info[.mediaURL] as? URL {
            var filename = movieUrl.lastPathComponent;
            if let idx = filename.lastIndex(of: ".") {
                filename = String(filename.prefix(upTo: idx));
                if filename.hasPrefix("trim.") {
                    filename = String(filename.dropFirst("trim.".count));
                }
            }

            upload(movieUrl: movieUrl, filename: filename);
        } else if let imageUrl = info[.imageURL] as? URL {
            var filename = imageUrl.lastPathComponent;
            if let idx = filename.lastIndex(of: ".") {
                filename = String(filename.prefix(upTo: idx));
                if filename.hasPrefix("trim.") {
                    filename = String(filename.dropFirst("trim.".count));
                }
            }

            upload(imageUrl: imageUrl, filename: filename);
        } else if let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
            MediaHelper.askImageQuality(controller: self, forceQualityQuestion: self.askMediaQuality, { result in
                self.askMediaQuality = false;
                switch result {
                case .success(let quality):
                    MediaHelper.compressImage(image: image, filename: UUID().uuidString, quality: quality, completionHandler: { result in
                        switch result {
                        case .success(let fileUrl):
                            self.uploadFile(url: fileUrl, filename: fileUrl.lastPathComponent, deleteSource: true);
                        case .failure(let error):
                            self.showAlert(shareError: error);
                        }
                    })
                case .failure(_):
                    return;
                }
            });
        }
        
        picker.dismiss(animated: true, completion: nil);
    }
    
    func upload(imageUrl url: URL, filename: String) {
        MediaHelper.askImageQuality(controller: self, forceQualityQuestion: self.askMediaQuality, { result in
            self.askMediaQuality = false;
            switch result {
            case .success(let quality):
                MediaHelper.compressImage(url: url, filename: filename, quality: quality, deleteSource: true, completionHandler: { result in
                    switch result {
                    case .success(let fileUrl):
                        self.uploadFile(url: fileUrl, filename: fileUrl.lastPathComponent, deleteSource: true);
                    case .failure(let error):
                        self.showAlert(shareError: error);
                    }
                })
            case .failure(_):
                return;
            }
        });
    }
    
    func upload(movieUrl url: URL, filename: String) {
        MediaHelper.askVideoQuality(controller: self, forceQualityQuestion: self.askMediaQuality, { result in
            self.askMediaQuality = false;
            switch result {
            case .success(let quality):
                DispatchQueue.main.async {
                    self.showProgressBar();
                    MediaHelper.compressMovie(url: url, filename: filename, quality: quality, deleteSource: true, progressCallback: { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.progressBar?.progress = progress;
                        }
                    }, completionHandler: { result in
                        DispatchQueue.main.async {
                            self.hideProgressBar();
                        }
                        switch result {
                        case .success(let fileUrl):
                            self.uploadFile(url: fileUrl, filename: fileUrl.lastPathComponent, deleteSource: true);
                        case .failure(let error):
                            self.showAlert(shareError: error);
                        }
                    })
                }
            case .failure(_):
                return;
            }
        });
    }
    
    private func copyFileLocally(url: URL, defaultSuffix: String) -> (URL, String, String)? {
        var filename = url.lastPathComponent;
        var suffix = defaultSuffix;
        if let idx = filename.lastIndex(of: ".") {
            suffix = String(filename.suffix(from: filename.index(after: idx)));
            filename = String(filename.prefix(upTo: idx));
            if filename.hasPrefix("trim.") {
                filename = String(filename.dropFirst("trim.".count));
            }
        }
        
        let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + suffix, isDirectory: false);
        do {
            try FileManager.default.copyItem(at: url, to: tmpUrl);
        } catch {
            return nil;
        }
        return (tmpUrl, filename, suffix);
    }
        
    private func uploadFile(url fileUrl: URL, filename: String, deleteSource: Bool) {
        self.share(filename: filename, url: fileUrl, completionHandler: { result in
            switch result {
            case .success(let uploadedUrl, let filesize, let mimetype):
                print("file uploaded to:", uploadedUrl);
                var appendix = ChatAttachmentAppendix()
                appendix.filename = filename;
                appendix.filesize = filesize
                appendix.mimetype = mimetype;
                appendix.state = .downloaded;

                self.sendAttachment(originalUrl: fileUrl, uploadedUrl: uploadedUrl.absoluteString, appendix: appendix, completionHandler: {
                    if deleteSource && FileManager.default.fileExists(atPath: fileUrl.path) {
                        try? FileManager.default.removeItem(at: fileUrl);
                    }
                });
            case .failure(let error):
                self.showAlert(shareError: error);
            }
        })
    }
    
}
 
