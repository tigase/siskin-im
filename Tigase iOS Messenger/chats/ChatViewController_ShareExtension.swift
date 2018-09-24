//
// BaseChatViewControllerWithShare.swift
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
import TigaseSwift

protocol BaseChatViewController_ShareImageExtension: class {
    
    var progressBar: UIProgressView! { get set }
    var shareButton: UIButton! { get set }
    
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate? { get set }
    
    var xmppService: XmppService! { get }
    var account: BareJID! { get }
    var jid: JID! { get }
    
    
    func sendMessage(body: String, additional: [Element], preview: String?, completed: (()->Void)?);
    
    func present(_ controller: UIViewController, animated: Bool, completion: (()->Void)?);
}

extension BaseChatViewController_ShareImageExtension {
    
    func initSharing() {
        shareButton.isEnabled = Settings.SharingViaHttpUpload.getBool();
    }
    
    func showPhotoSelector(_ sender: UIView) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { (action) in
                self.selectPhoto(.camera);
            }));
            alert.addAction(UIAlertAction(title: "Select photo", style: .default, handler: { (action) in
                self.selectPhoto(.photoLibrary);
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            alert.popoverPresentationController?.sourceView = sender;
            alert.popoverPresentationController?.sourceRect = sender.bounds;
            present(alert, animated: true, completion: nil);
        } else {
            selectPhoto(.photoLibrary);
        }
    }
    
    func selectPhoto(_ source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController();
        self.imagePickerDelegate = BaseChatViewController_ShareImagePickerDelegate(self);
        picker.delegate = self.imagePickerDelegate;
        picker.allowsEditing = false;//true;
        picker.sourceType = source;
        present(picker, animated: true, completion: nil);
    }

}

class BaseChatViewController_ShareImagePickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, URLSessionDelegate, URLSessionTaskDelegate {
    
    let controller: BaseChatViewController_ShareImageExtension;
    
    init(_ controller: BaseChatViewController_ShareImageExtension) {
        self.controller = controller;
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingImage image: UIImage, editingInfo info: [String : AnyObject]?) {
        let photo = (info?[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.editedImage)] as? UIImage) ?? image;
        print("photo", photo.size, "image", image.size, "originalImage", info?[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as Any);
        let imageName = "image.jpg";
        
        // saving photo
        let data = photo.jpegData(compressionQuality: 0.9);
        picker.dismiss(animated: true, completion: nil);
        
        if data != nil, let client = self.controller.xmppService.getClient(forJid: self.controller.account) {
            let httpUploadModule: HttpFileUploadModule = client.modulesManager.getModule(HttpFileUploadModule.ID)!;
            httpUploadModule.findHttpUploadComponent(onSuccess: { (results) in
                let size = data!.count;
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
                        self.showAlert(title: "Upload failed", message: "Feature not supported by XMPP server");
                        return;
                    }
                    self.showAlert(title: "Upload failed", message: "Selected image is too big!");
                    return;
                }
                
                httpUploadModule.requestUploadSlot(componentJid: compJid!, filename: imageName, size: size, contentType: "image/jpeg", onSuccess: { (slot) in
                    DispatchQueue.main.async {
                        self.controller.progressBar.isHidden = false;
                    }
                    var request = URLRequest(url: URL(string: slot.putUri)!);
                    slot.putHeaders.forEach({ (k,v) in
                        request.addValue(v, forHTTPHeaderField: k);
                    });
                    request.httpMethod = "PUT";
                    request.httpBody = data;
                    request.addValue("image/jpeg", forHTTPHeaderField: "Content-Type");
                    let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main);
                    session.dataTask(with: request) { (data, response, error) in
                        guard error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 500) == 201 else {
                            self.showAlert(title: "Upload failed", message: "Upload to HTTP server failed.");
                            return;
                        }
                        let x = Element(name: "x", xmlns: "jabber:x:oob");
                        x.addChild(Element(name: "url", cdata: slot.getUri));
                        
                        ImageCache.shared.set(image: image) { (key) in
                            self.controller.sendMessage(body: slot.getUri, additional: [x], preview: key == nil ? nil : "preview:image:\(key!)", completed: nil);
                        }
                        }.resume();
                }, onError: { (error, message) in
                    self.showAlert(title: "Upload failed", message: message ?? "Please try again later.");
                })
            }, onError: { (error) in
                if error != nil && error! == ErrorCondition.item_not_found {
                    self.showAlert(title: "Upload failed", message: "Feature not supported by XMPP server");
                } else {
                    self.showAlert(title: "Upload failed", message: "Please try again later.");
                }
            })
        }
        controller.imagePickerDelegate = nil;
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.controller.progressBar.isHidden = false;
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.controller.present(alert, animated: true, completion: nil);
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        controller.imagePickerDelegate = nil;
        picker.dismiss(animated: true, completion: nil);
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.controller.progressBar.progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend);
        if self.controller.progressBar.progress == 1.0 {
            self.controller.progressBar.isHidden = true;
            self.controller.progressBar.progress = 0;
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
