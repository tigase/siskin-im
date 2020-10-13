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

extension ChatViewInputBar {
        
    class ShareImageButton: ShareButton {
        
        override func execute(_ sender: Any) {
            controller?.selectPhoto(.photoLibrary)
        }
        
        override func setup() {
            super.setup();
            if #available(iOS 13.0, *) {
                let image = UIImage(systemName: "photo");
                setImage(image, for: .normal);
            } else {
                setImage(UIImage(named: "photo"), for: .normal);
            }
        }
    }
    
    class ShareCameraImageButton: ShareButton {
        
        override func execute(_ sender: Any) {
            controller?.selectPhoto(.camera)
        }
        
        override func setup() {
            super.setup();
            if #available(iOS 13.0, *) {
                let image = UIImage(systemName: "camera");
                setImage(image, for: .normal);
            } else {
                setImage(UIImage(named: "camera"), for: .normal);
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
        guard let fileUrl = (info[UIImagePickerController.InfoKey.mediaURL] as? URL) ?? (info[UIImagePickerController.InfoKey.imageURL] as? URL) else {
            return;
        }
        
        var filename = fileUrl.lastPathComponent;
        if filename.hasPrefix("trim.") {
            filename = String(filename.dropFirst("trim.".count));
        }
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
                    if FileManager.default.fileExists(atPath: fileUrl.path) {
                        try? FileManager.default.removeItem(at: fileUrl);
                    }
                });
            case .failure(let error):
                self.showAlert(shareError: error);
            }
        })
        picker.dismiss(animated: true, completion: nil);
    }

}
 
