//
// BaseChatViewControllerWithShare.swift
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
import TigaseSwift
import Shared

protocol BaseChatViewController_ShareImageExtension: class {
    
    var chatViewInputBar: ChatViewInputBar { get }
    
    var progressBar: UIProgressView? { get set }
    
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate? { get set }
    var filePickerDelegate: BaseChatViewController_ShareFilePickerDelegate? { get set }
    
    var chat: DBChatProtocol! { get }
    var account: BareJID! { get }
    var jid: BareJID! { get }
    
    func sendAttachment(originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (()->Void)?);
        
    func present(_ controller: UIViewController, animated: Bool, completion: (()->Void)?);
        
}

extension ChatViewInputBar {
    class ShareButton: UIButton {
        
        weak var delegate: BaseChatViewController_ShareImageExtension?;
                
        init(delegate: BaseChatViewController_ShareImageExtension) {
            self.delegate = delegate;
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
            if #available(iOS 13.0, *) {
            } else {
                self.widthAnchor.constraint(equalTo: heightAnchor).isActive = true;
                self.heightAnchor.constraint(equalToConstant: 24).isActive = true;
            }
        }
    }
    
    class ShareFileButton: ShareButton {
        
        override func execute(_ sender: Any) {
            delegate?.selectFile();
        }
        
        override func setup() {
            super.setup();
            if #available(iOS 13.0, *) {
                let image = UIImage(systemName: "arrow.up.doc");
                setImage(image, for: .normal);
            } else {
                setImage(UIImage(named: "arrow.up.doc"), for: .normal);
            }
        }
    }
    
    class ShareImageButton: ShareButton {
        
        override func execute(_ sender: Any) {
            delegate?.selectPhoto(.photoLibrary)
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
            delegate?.selectPhoto(.camera)
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


extension BaseChatViewController_ShareImageExtension {
            
    func selectPhoto(_ source: UIImagePickerController.SourceType) {
        guard checkIfEnabledOrAsk(completionHandler: { [weak self] in self?.selectPhoto(source); }) else {
            return;
        }
        let picker = UIImagePickerController();
        self.imagePickerDelegate = BaseChatViewController_ShareImagePickerDelegate(self);
        picker.delegate = self.imagePickerDelegate;
        picker.allowsEditing = false;//true;
        picker.sourceType = source;
        present(picker, animated: true, completion: nil);
    }
    
    func selectFile() {
        guard checkIfEnabledOrAsk(completionHandler: { [weak self] in self?.selectFile(); }) else {
            return;
        }
        let picker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeData)], in: .open);
        self.filePickerDelegate = BaseChatViewController_ShareFilePickerDelegate(self);
        picker.delegate = self.filePickerDelegate;
        picker.allowsMultipleSelection = false;
        self.present(picker, animated: true, completion: nil);
    }
    
    private func checkIfEnabledOrAsk(completionHandler: @escaping ()->Void) -> Bool {
        guard Settings.SharingViaHttpUpload.getBool() else {
            let alert = UIAlertController(title: "Question", message: "When you share files, they are uploaded to HTTP server with unique URL. Anyone who knows the unique URL to the file is able to download it.\nDo you wish to proceed?", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action) in
                Settings.SharingViaHttpUpload.setValue(true);
                completionHandler();
            }));
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
            present(alert, animated: true, completion: nil);

            return false;
        }
        return true;
    }
    
    func initializeSharing() {
        self.chatViewInputBar.addBottomButton(ChatViewInputBar.ShareFileButton(delegate: self));
        self.chatViewInputBar.addBottomButton(ChatViewInputBar.ShareImageButton(delegate: self));
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            self.chatViewInputBar.addBottomButton(ChatViewInputBar.ShareCameraImageButton(delegate: self));
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
}

enum ShareError: Error {
    case unknownError
    case noAccessError
    case noFileSizeError
    case noMimeTypeError
    
    case notSupported
    case fileTooBig
    
    case httpError
    
    var message: String {
        switch self {
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

class BaseChatViewController_SharePickerDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
 
    let controller: BaseChatViewController_ShareImageExtension;
    
    init(_ controller: BaseChatViewController_ShareImageExtension) {
        self.controller = controller;
    }

    func share(filename: String, url: URL, completionHandler: @escaping (UploadResult)->Void) {
        guard url.startAccessingSecurityScopedResource() else {
            completionHandler(.failure(.noAccessError));
            return;
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey]), let size = values.fileSize else {
            url.stopAccessingSecurityScopedResource();
            completionHandler(.failure(.noFileSizeError));
            return;
        }
        
        var mimeType: String? = nil;
        
        if let type = values.typeIdentifier {
            mimeType = UTTypeCopyPreferredTagWithClass(type as CFString, kUTTagClassMIMEType)?.takeRetainedValue() as String?;
        }
        
        let encrypted = ((self.controller.chat as? DBChat)?.options.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!) == .omemo;

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
            url.stopAccessingSecurityScopedResource();

            guard let inputStream = InputStream(url: dataConsumer.url) else {
                completionHandler(.failure(.noAccessError));
                return;
            }
            self.share(filename: filename, inputStream: inputStream, filesize: dataConsumer.size, mimeType: mimeType ?? "application/octet-stream", completionHandler: { result in
                // we cannot release dataConsumer before the file is uploaded!
                var tmp = dataConsumer;
                switch result {
                case .success(let url):
                    var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                    parts.scheme = "aesgcm";
                    parts.fragment = (iv + key).map({ String(format: "%02x", $0) }).joined();
                    let shareUrl = parts.url!;
                    
                    print("sending url:", shareUrl.absoluteString);
                    completionHandler(.success(url: shareUrl, filesize: size, mimeType: mimeType));
                case .failure(let error):
                    completionHandler(.failure(error));
                }
            });
        } else {
            guard let inputStream = InputStream(url: url) else {
                url.stopAccessingSecurityScopedResource();
                completionHandler(.failure(.noAccessError));
                return;
            }
            self.share(filename: filename, inputStream: inputStream, filesize: size, mimeType: mimeType ?? "application/octet-stream", completionHandler: { result in
                url.stopAccessingSecurityScopedResource();
                switch result {
                case .success(let getUri):
                    completionHandler(.success(url: getUri, filesize: size, mimeType: mimeType));
                case .failure(let error):
                    completionHandler(.failure(error));
                }
            });
        }
    }
            
    func share(filename: String, inputStream: InputStream, filesize size: Int, mimeType: String, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        if let client = XmppService.instance.getClient(forJid: self.controller.account) {
            let httpUploadModule: HttpFileUploadModule = client.modulesManager.getModule(HttpFileUploadModule.ID)!;
            httpUploadModule.findHttpUploadComponent(onSuccess: { (results) in
                var compJid: JID? = nil;
                results.forEach({ (k,v) in
                    if compJid != nil {
                        return;
                    }
                    if v != nil && v! < size {
                        return;
                    }
                    compJid = k;
                });

                guard compJid != nil else {
                    guard results.count > 0 else {
                        completionHandler(.failure(.notSupported));
                        return;
                    }
                    completionHandler(.failure(.fileTooBig));
                    return;
                }
            
                httpUploadModule.requestUploadSlot(componentJid: compJid!, filename: filename, size: size, contentType: mimeType, onSuccess: { (slot) in
                    DispatchQueue.main.async {
                        self.controller.showProgressBar();
                    }
                    var request = URLRequest(url: slot.putUri);
                    slot.putHeaders.forEach({ (k,v) in
                        request.addValue(v, forHTTPHeaderField: k);
                    });
                    request.httpMethod = "PUT";
                    request.httpBodyStream = inputStream;
                    request.addValue(String(size), forHTTPHeaderField: "Content-Length");
                    request.addValue(mimeType, forHTTPHeaderField: "Content-Type");
                    let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main);
                    session.dataTask(with: request) { (data, response, error) in
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 500;
                        guard error == nil && (code == 200 || code == 201) else {
                            print("error:", error as Any, "response:", response as Any)
                            completionHandler(.failure(.httpError));
                            return;
                        }
                        if code == 200 {
                            DispatchQueue.main.async {
                                let alert = UIAlertController(title: "Warning", message: "File upload completed but it was not confirmed correctly by your server. Do you wish to proceed anyway?", preferredStyle: .alert);
                                alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { action in
                                    completionHandler(.success(slot.getUri));
                                }))
                                alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                                self.controller.present(alert, animated: true, completion: nil);
                            }
                        } else {
                            completionHandler(.success(slot.getUri));
                        }
                        }.resume();
                }, onError: { (error, message) in
                    completionHandler(.failure(.unknownError));
                })
            }, onError: { (error) in
                if error != nil && error! == ErrorCondition.item_not_found {
                    completionHandler(.failure(.notSupported));
                } else {
                    completionHandler(.failure(.unknownError));
                }
            })
        }
    }
    
    func showAlert(shareError: ShareError) {
        self.showAlert(title: "Upload failed", message: shareError.message);
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.controller.hideProgressBar();
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.controller.present(alert, animated: true, completion: nil);
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.controller.progressBar?.progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend);
        if self.controller.progressBar?.progress == 1.0 {
            self.controller.hideProgressBar();
            self.controller.progressBar?.progress = 0;
        }
    }
    
    enum UploadResult {
        case success(url: URL, filesize: Int, mimeType: String?)
        case failure(ShareError)
        
    }
}

class BaseChatViewController_ShareFilePickerDelegate: BaseChatViewController_SharePickerDelegate, UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return;
        }
        print("url:", url);
        controller.dismiss(animated: true, completion: nil);
        self.controller.filePickerDelegate = nil;
                    
        share(filename: url.lastPathComponent, url: url) { (result) in
            switch result {
            case .success(let uploadedUrl, let filesize, let mimetype):
                print("file uploaded to:", uploadedUrl);
                var appendix = ChatAttachmentAppendix()
                appendix.filename = url.lastPathComponent;
                appendix.filesize = filesize;
                appendix.mimetype = mimetype;
                appendix.state = .downloaded;
                _ = url.startAccessingSecurityScopedResource();
                self.controller.sendAttachment(originalUrl: url, uploadedUrl: uploadedUrl.absoluteString, appendix: appendix, completionHandler: {
                    url.stopAccessingSecurityScopedResource();
                });
            case .failure(let error):
                self.showAlert(shareError: error);
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.controller.filePickerDelegate = nil;
        controller.dismiss(animated: true, completion: nil);
    }
    
}

class BaseChatViewController_ShareImagePickerDelegate: BaseChatViewController_SharePickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @objc func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        controller.imagePickerDelegate = nil;
        picker.dismiss(animated: true, completion: nil);
    }
    
    @objc func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        guard let photo = (info[UIImagePickerController.InfoKey.editedImage] as? UIImage) ?? (info[UIImagePickerController.InfoKey.originalImage] as? UIImage) else {
            return;
        }
        print("photo", photo.size, "originalImage", info[UIImagePickerController.InfoKey.originalImage] as Any);
        
        // saving photo
        let data = photo.jpegData(compressionQuality: 0.9);
        picker.dismiss(animated: true, completion: nil);
        if data != nil {
            let encrypted = ((self.controller.chat as? DBChat)?.options.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!) == .omemo;

            if encrypted {
                var iv = Data(count: 12);
                iv.withUnsafeMutableBytes { (bytes) -> Void in
                    _ = SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!);
                }

                var key = Data(count: 32);
                key.withUnsafeMutableBytes { (bytes) -> Void in
                    _ = SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!);
                }
                
                let dataProvider = Cipher.DataDataProvider(data: data!);
                let dataConsumer = Cipher.TempFileConsumer()!;
                
                let cipher = Cipher.AES_GCM();
                let tag = cipher.encrypt(iv: iv, key: key, provider: dataProvider, consumer: dataConsumer);
                _ = dataConsumer.consume(data: tag);
                dataConsumer.close();
                
                self.share(filename: "image.jpg", inputStream: InputStream(url: dataConsumer.url)!, filesize: dataConsumer.size, mimeType: "image/jpeg") { (result) in
                    // we cannot release dataConsumer before the file is uploaded!
                    var tmp = dataConsumer;
                    switch result {
                    case .success(let getUri):
                        print("file uploaded to:", getUri);
                        var appendix = ChatAttachmentAppendix()
                        appendix.filename = "image.jpg";
                        appendix.filesize = data!.count;
                        appendix.mimetype = "image/jpeg";
                        appendix.state = .downloaded;
                        
                        var url: URL? = FileManager.default.temporaryDirectory.appendingPathComponent("image.jpg", isDirectory: false);
                        do {
                            try data!.write(to: url!);
                        } catch {
                            url = nil;
                        }
                        
                        var parts = URLComponents(url: getUri, resolvingAgainstBaseURL: true)!;
                        parts.scheme = "aesgcm";
                        parts.fragment = (iv + key).map({ String(format: "%02x", $0) }).joined();
                        let shareUrl = parts.url!;
                        
                        print("sending url:", shareUrl.absoluteString);
                        self.controller.sendAttachment(originalUrl: url, uploadedUrl: shareUrl.absoluteString, appendix: appendix, completionHandler: {
                            // attachment was sent..
                            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.removeItem(at: url);
                            }
                        })
                    case .failure(let error):
                        self.showAlert(shareError: error);
                    }
                }
            } else {
            self.share(filename: "image.jpg", inputStream: InputStream(data: data!), filesize: data!.count, mimeType: "image/jpeg") { (result) in
                switch result {
                case .success(let getUri):
                    print("file uploaded to:", getUri);
                    var appendix = ChatAttachmentAppendix()
                    appendix.filename = "image.jpg";
                    appendix.filesize = data!.count;
                    appendix.mimetype = "image/jpeg";
                    appendix.state = .downloaded;
                    
                    var url: URL? = FileManager.default.temporaryDirectory.appendingPathComponent("image.jpg", isDirectory: false);
                    do {
                        try data!.write(to: url!);
                    } catch {
                        url = nil;
                    }
                    
                    self.controller.sendAttachment(originalUrl: url, uploadedUrl: getUri.absoluteString, appendix: appendix, completionHandler: {
                        // attachment was sent..
                        if let url = url, FileManager.default.fileExists(atPath: url.path) {
                            try? FileManager.default.removeItem(at: url);
                        }
                    })
                case .failure(let error):
                    self.showAlert(shareError: error);
                }
            }
            }
        }
        controller.imagePickerDelegate = nil;
    }
    
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
