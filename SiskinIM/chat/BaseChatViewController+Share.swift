//
// BaseChatViewController+Share.swift
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
import MobileCoreServices
import Martin
import Shared

extension ChatViewInputBar {
    class ShareButton: UIButton {
        
        weak var controller: BaseChatViewController?;
                
        init(controller: BaseChatViewController) {
            self.controller = controller;
            super.init(frame: .zero);
            setup();
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder);
            setup();
        }
        
        @objc func execute(_ sender: Any) {
        }
        
        func setup() {
            self.tintColor = UIColor(named: "tintColor");
            self.addTarget(self, action: #selector(execute(_:)), for: .touchUpInside);
            self.contentMode = .scaleToFill;
            self.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4);
            if #available(iOS 13.0, *) {
            } else {
                self.widthAnchor.constraint(equalTo: heightAnchor).isActive = true;
                self.heightAnchor.constraint(equalToConstant: 24).isActive = true;
            }
        }
    }
    
}

import AVFoundation

extension ChatViewInputBar {
    class VoiceMessageButton: ShareButton {
        
        override func execute(_ sender: Any) {
            controller?.chatViewInputBar.voiceRecordingView.controller = controller;
            controller?.chatViewInputBar.startRecordingVoiceMessage(sender);
        }
        
        override func setup() {
            super.setup();
            let image = UIImage(systemName: "mic");
            setImage(image, for: .normal);
        }
    }
    
}


extension BaseChatViewController: URLSessionDelegate {
        
    func checkIfEnabledOrAsk(completionHandler: @escaping ()->Void) -> Bool {
        guard Settings.sharingViaHttpUpload else {
            let alert = UIAlertController(title: NSLocalizedString("Question", comment: "alert title"), message: NSLocalizedString("When you share files, they are uploaded to HTTP server with unique URL. Anyone who knows the unique URL to the file is able to download it.\nDo you wish to proceed?", comment: "alert body"), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .default, handler: { (action) in
                Settings.sharingViaHttpUpload = true;
                completionHandler();
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .cancel, handler: nil));
            present(alert, animated: true, completion: nil);

            return false;
        }
        return true;
    }
    
    func initializeSharing() {
        if AVAudioSession.sharedInstance().recordPermission != .denied {
            self.chatViewInputBar.addBottomButton(ChatViewInputBar.VoiceMessageButton(controller: self));
        }
        self.chatViewInputBar.addBottomButton(ChatViewInputBar.ShareFileButton(controller: self));
        self.chatViewInputBar.addBottomButton(ChatViewInputBar.ShareImageButton(controller: self));
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            self.chatViewInputBar.addBottomButton(ChatViewInputBar.ShareCameraImageButton(controller: self));
        }
    }
        
    func showProgressBar() {
        if self.progressBar == nil {
            let progressBar = UIProgressView(progressViewStyle: .bar);
            progressBar.translatesAutoresizingMaskIntoConstraints = false;
            self.progressBar = progressBar;
            self.chatViewInputBar.addSubview(progressBar);
            NSLayoutConstraint.activate([
                self.chatViewInputBar.topAnchor.constraint(equalTo: progressBar.topAnchor),
                self.chatViewInputBar.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
                self.chatViewInputBar.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor),
                self.chatViewInputBar.bottomAnchor.constraint(greaterThanOrEqualTo: progressBar.bottomAnchor)
            ]);
        }
        self.progressBar?.isHidden = false;
    }

    func hideProgressBar() {
        self.progressBar?.isHidden = true;
    }
    fileprivate func shouldEncryptUploadedFile() -> Bool {
        switch self.conversation {
        case let chat as Chat:
            return chat.options.encryption ?? Settings.messageEncryption == .omemo;
        case let room as Room:
            let encryption: ChatEncryption = room.options.encryption ?? (room.features.contains(.omemo) ? Settings.messageEncryption : .none);
            
            guard encryption == .none || room.features.contains(.omemo) else {
                return true;
            }
            return encryption == .omemo;
        default:
            return false;
        }
    }

    func share(filename: String, url: URL, mimeType suggestedMimeType: String? = nil, completionHandler: @escaping (HTTPFileUploadHelper.UploadResult)->Void) {
        guard let context = self.conversation.context else {
            completionHandler(.failure(.unknownError));
            return;
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey]), let size = values.fileSize else {
            completionHandler(.failure(.noFileSizeError));
            return;
        }
        
        DispatchQueue.main.async {
            self.showProgressBar();
        }

        var mimeType: String? = nil;
        
        if suggestedMimeType != nil {
            mimeType = suggestedMimeType;
        } else {
            if let type = values.typeIdentifier {
                mimeType = UTTypeCopyPreferredTagWithClass(type as CFString, kUTTagClassMIMEType)?.takeRetainedValue() as String?;
            }
        }
        
        let encrypted = shouldEncryptUploadedFile();

        if encrypted {
            var iv = Data(count: 12);
            iv.withUnsafeMutableBytes { (bytes) -> Void in
                _ = SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!);
            }

            var key = Data(count: 32);
            key.withUnsafeMutableBytes { (bytes) -> Void in
                _ = SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!);
            }

            let dataProvider = Cipher.FileDataProvider(inputStream: InputStream(url: url)!);
            let dataConsumer = Cipher.TempFileConsumer()!;
            
            let cipher = Cipher.AES_GCM();
            let tag = cipher.encrypt(iv: iv, key: key, provider: dataProvider, consumer: dataConsumer);
            _ = dataConsumer.consume(data: tag);
            dataConsumer.close();

            guard let inputStream = InputStream(url: dataConsumer.url) else {
                DispatchQueue.main.async {
                    self.hideProgressBar();
                }
                completionHandler(.failure(.noAccessError));
                return;
            }
            HTTPFileUploadHelper.upload(for: context, filename: filename, inputStream: inputStream, filesize: dataConsumer.size, mimeType: mimeType ?? "application/octet-stream", delegate: self, completionHandler: { result in
                // we cannot release dataConsumer before the file is uploaded!
                var tmp = dataConsumer;
                switch result {
                case .success(let url):
                    var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                    parts.scheme = "aesgcm";
                    parts.fragment = (iv + key).map({ String(format: "%02x", $0) }).joined();
                    let shareUrl = parts.url!;
                    
                    completionHandler(.success(url: shareUrl, filesize: size, mimeType: mimeType));
                case .failure(let error):
                    completionHandler(.failure(error));
                }
                DispatchQueue.main.async {
                    self.hideProgressBar();
                }
            });
        } else {
            guard let inputStream = InputStream(url: url) else {
                DispatchQueue.main.async {
                    self.hideProgressBar();
                }
                completionHandler(.failure(.noAccessError));
                return;
            }
            HTTPFileUploadHelper.upload(for: context, filename: filename, inputStream: inputStream, filesize: size, mimeType: mimeType ?? "application/octet-stream", delegate: self, completionHandler: { result in
                switch result {
                case .success(let getUri):
                    completionHandler(.success(url: getUri, filesize: size, mimeType: mimeType));
                case .failure(let error):
                    completionHandler(.failure(error));
                }
                DispatchQueue.main.async {
                    self.hideProgressBar();
                }
            });
        }
    }
            
    func showAlert(shareError: ShareError) {
        self.showAlert(title: NSLocalizedString("Upload failed", comment: "alert title"), message: shareError.message);
    }
    
    func showAlert(error: Error) {
        if let shareError = error as? ShareError {
            self.showAlert(shareError: shareError);
        } else {
            self.showAlert(title: NSLocalizedString("Upload failed", comment: "alert title"), message: error.localizedDescription);
        }
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.hideProgressBar();
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.progressBar?.progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend);
        if self.progressBar?.progress == 1.0 {
            self.hideProgressBar();
            self.progressBar?.progress = 0;
        }
    }
    
}
