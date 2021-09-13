//
// BaseChatViewController+ShareFile.swift
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
import Foundation
import UIKit
import MobileCoreServices

extension ChatViewInputBar {
    
    class ShareFileButton: ShareButton {
        
        override func execute(_ sender: Any) {
            controller?.selectFile();
        }
        
        override func setup() {
            super.setup();
            let image = UIImage(systemName: "arrow.up.doc");
            setImage(image, for: .normal);
        }
    }

}


extension BaseChatViewController: UIDocumentPickerDelegate {
    
    func selectFile() {
        guard checkIfEnabledOrAsk(completionHandler: { [weak self] in self?.selectFile(); }) else {
            return;
        }
        let picker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeData)], in: .open);
        picker.delegate = self;
        picker.allowsMultipleSelection = false;
        self.present(picker, animated: true, completion: nil);
    }

    @objc func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return;
        }
        controller.dismiss(animated: true, completion: nil);
                    
        guard url.startAccessingSecurityScopedResource() else {
            url.stopAccessingSecurityScopedResource();
            self.showAlert(shareError: .noAccessError);
            return;
        }
        share(filename: url.lastPathComponent, url: url) { (result) in
            switch result {
            case .success(let uploadedUrl, let filesize, let mimetype):
                url.stopAccessingSecurityScopedResource();
                var appendix = ChatAttachmentAppendix()
                appendix.filename = url.lastPathComponent;
                appendix.filesize = filesize;
                appendix.mimetype = mimetype;
                appendix.state = .downloaded;
                _ = url.startAccessingSecurityScopedResource();
                self.sendAttachment(originalUrl: url, uploadedUrl: uploadedUrl.absoluteString, appendix: appendix, completionHandler: {
                    url.stopAccessingSecurityScopedResource();
                });
            case .failure(let error):
                self.showAlert(shareError: error);
            }
        }
    }
    
    @objc func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true, completion: nil);
    }

}
