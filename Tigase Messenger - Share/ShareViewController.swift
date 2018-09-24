//
// ShareViewController.swift
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
import Social
import TigaseSwift
import MobileCoreServices

class ShareViewController: SLComposeServiceViewController {
    
    var account: String? = nil;
    var recipients: [JID] = [];
    
    weak var handler: EventHandler?;
    
    lazy var xmppClient: XMPPClient = {
        let client = XMPPClient();
        let sslHandler: ((SessionObject, SecTrust)->Bool) = {(sessionObject,secTrust) -> Bool in
            return true;
        };
        client.sessionObject.setProperty(SocketConnector.SSL_CERTIFICATE_VALIDATOR, value: sslHandler);
        _ = client.modulesManager.register(AuthModule());
        _ = client.modulesManager.register(StreamFeaturesModule());
        _ = client.modulesManager.register(SaslModule());
        _ = client.modulesManager.register(ResourceBinderModule());
        _ = client.modulesManager.register(SessionEstablishmentModule());
        _ = client.modulesManager.register(DiscoveryModule());
        client.modulesManager.register(PresenceModule()).initialPresence = false;
        let messageModule = client.modulesManager.register(MessageModule());
        let rosterModule =  client.modulesManager.register(RosterModule());
        _ = client.modulesManager.register(HttpFileUploadModule());
        
        let handler = ShareEventHandler();
        handler.controller = self;
        self.handler = handler;
        
        client.eventBus.register(handler: handler, for: RosterModule.ItemUpdatedEvent.TYPE)
        return client;
    }();
    
    lazy var accountConfigurationItem: SLComposeSheetConfigurationItem = {
        let item = SLComposeSheetConfigurationItem()!;
        item.title = "Account";
        item.tapHandler = self.showAccountSelection;
        return item;
    }();
    
    lazy var buddiesConfigurationItem: SLComposeSheetConfigurationItem = {
        let item = SLComposeSheetConfigurationItem()!;
        item.title = "Recipients";
        item.tapHandler = self.showRecipientsSelection;
        return item;
    }();

    weak var rosterController: RecipientsSelectionViewController?;
    
    var webUrl: URL?;
    
    var sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share");
    
    override func isContentValid() -> Bool {
        return account != nil && xmppClient.state == .connected && recipients.count > 0;
    }
    
    override func presentationAnimationDidFinish() {
        if !sharedDefaults!.bool(forKey: "SharingViaHttpUpload") {
            var error = true;
            if let provider = (self.extensionContext!.inputItems.first as? NSExtensionItem)?.attachments?.first {
                error = !provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String);
            }
            if error {
                self.showAlert(title: "Failure", message: "Sharing feature with HTTP upload is disabled within application. To use this feature you need to enable sharing with HTTP upload in application");
            }
        }
    }
    
    override func didSelectPost() {
        if let provider = (self.extensionContext!.inputItems.first as? NSExtensionItem)?.attachments?.first {
            if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil, completionHandler: { (value, error) in
                    self.shareText(url: value as! URL);
                })
            } else {
                if let type = [kUTTypeFileURL, kUTTypeImage, kUTTypeMovie].filter({ (it) -> Bool in
                    return provider.hasItemConformingToTypeIdentifier(it as String);
                }).first {
                    provider.loadItem(forTypeIdentifier: type as String, options: nil, completionHandler: { (item, error) in
                        if let localUrl = item as? URL {
                            let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, localUrl.pathExtension as CFString, nil)?.takeRetainedValue();
                            self.upload(localUrl: localUrl, type: uti != nil ? (UTTypeCopyPreferredTagWithClass(uti!, kUTTagClassMIMEType)?.takeRetainedValue() as String?) : nil, handler: {(remoteUrl) in
                                guard remoteUrl != nil else {
                                    self.showAlert(title: "Failure", message: "Please try again later.");
                                    return;
                                }
                                self.shareText(url: remoteUrl!);
                            });
                        } else {
                            self.showAlert(title: "Failure", message: "Please try again later.");
                        }
                    })
                }
            }
        }
    }
    
    override func didSelectCancel() {
        xmppClient.disconnect(true);
        super.didSelectCancel();
    }
    
    override func configurationItems() -> [Any]! {
        return [accountConfigurationItem, buddiesConfigurationItem];
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: {(action) in
                self.extensionContext?.cancelRequest(withError: ShareError.failure);
            }));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    func showAccountSelection() {
        if xmppClient.state != .disconnected {
            xmppClient.disconnect(true);
        }
        let controller = storyboard?.instantiateViewController(withIdentifier: "accountSelectionViewController") as! AccountsTableViewController;
//        let controller = AccountsTableViewController(style: .plain);
        controller.selected = account;
        controller.delegate = self;
        pushConfigurationViewController(controller);
    }
    
    func accountSelection(account: String) {
        self.account = account;
        self.recipients = [];
        validateContent();
        self.buddiesConfigurationItem.value = "";
        accountConfigurationItem.value = account;
        xmppClient.connectionConfiguration.setUserJID(BareJID(account)!);
        
        if let password = getAccountPassword() {
            xmppClient.connectionConfiguration.setUserPassword(password);
            if let rosterStore: RosterStore = xmppClient.sessionObject.getProperty(RosterModule.ROSTER_STORE_KEY) {
                rosterStore.cleared();
            }
            xmppClient.login();
        }
    }
    
    func showRecipientsSelection() {
        guard account != nil else {
            return;
        }
        let controller = storyboard?.instantiateViewController(withIdentifier: "recipientsSelectionViewController") as! RecipientsSelectionViewController;
        controller.selected = recipients;
        controller.xmppClient = xmppClient;
        controller.delegate = self;
        self.rosterController = controller;
        pushConfigurationViewController(controller);
    }
    
    func recipientsChanged(_ recipients: [JID]) {
        self.recipients = recipients;
        buddiesConfigurationItem.value = String(recipients.count);
        validateContent();
    }
    
    func getAccountPassword() -> String? {
        guard account != nil else {
            return nil;
        }
        let query: [String: NSObject] = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(kSecReturnData) : kCFBooleanTrue, String(kSecAttrService) : "xmpp" as NSObject, String(kSecAttrAccount) : account! as NSObject ];
        
        var result:AnyObject?;
        
        let lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
        }
        
        if lastResultCode == noErr {
            if let data = result as? NSData {
                return String(data: data as Data, encoding: String.Encoding.utf8);
            }
        }
        return nil;
    }
    
    func upload(localUrl: URL, type: String?, handler: (URL?)->Void) {
        let size = try! FileManager.default.attributesOfItem(atPath: localUrl.path)[FileAttributeKey.size] as! UInt64;
        print("trying to upload", localUrl, "size", size, "type", type as Any);
        if let httpModule: HttpFileUploadModule = self.xmppClient.modulesManager.getModule(HttpFileUploadModule.ID) {
            httpModule.findHttpUploadComponent(onSuccess: { (results) in
                guard !results.isEmpty else {
                    self.showAlert(title: "Upload failed", message: "Feature not supported by XMPP server");
                    return;
                }
                
                let compJid = results.filter({ (k,v) -> Bool in
                    return v == nil || v! >= Int(size);
                }).first?.key;
                
                guard compJid != nil else {
                    self.showAlert(title: "Upload failed", message: "Selected object is too big!");
                    return;
                }
                
                httpModule.requestUploadSlot(componentJid: compJid!, filename: localUrl.pathComponents.last!, size: Int(size), contentType: type ?? "application/octet-stream", onSuccess: {(slot) in
                    print("allocated slot", slot.getUri, slot.putUri);
                    var request = URLRequest(url: URL(string: slot.putUri)!);
                    slot.putHeaders.forEach({ (k,v) in
                        request.addValue(v, forHTTPHeaderField: k);
                    });
                    request.httpMethod = "PUT";
//                    let inputStream = InputStream(url: localUrl);
//                    request.httpBodyStream = inputStream;
                    request.addValue(type ?? "application/octet-stream", forHTTPHeaderField: "Content-Type");
                    
                    URLSession.shared.uploadTask(with: request, fromFile: localUrl) { (data, response, error) in
                        guard error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 500) == 201 else {
                            print(data as Any, error as Any, response as Any);
                            self.showAlert(title: "Upload failed", message: "Upload to HTTP server failed.");
                            return;
                        }
                        self.shareText(url: URL(string: slot.getUri)!);
                    }.resume();
                }, onError: {(errorCondition, message) in
                    self.showAlert(title: "Upload failed", message: message ?? "Please try again later.");
                });
            }, onError: { (error) in
                if error != nil && error! == ErrorCondition.item_not_found {
                    self.showAlert(title: "Upload failed", message: "Feature not supported by XMPP server");
                } else {
                    self.showAlert(title: "Upload failed", message: "Please try again later.");
                }
            })
        } else {
            showAlert(title: "Upload failure", message: "Upload module not available!");
        }
    }
    
    func shareText(url: URL) {
        print("sharing", contentText, url);
        
        recipients.forEach { (recipient) in
            let message = Message();
            message.type = StanzaType.chat;
            message.to = recipient;
            message.body = contentText.isEmpty ? url.description : "\(contentText!) - \(url.description)";
            message.oob = url.description;
            xmppClient.context.writer?.write(message);
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2, execute: {
            self.xmppClient.disconnect();
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil);
        });
    }
    
    class ShareEventHandler: EventHandler {
        
        weak var controller: ShareViewController?;
        
        func handle(event: Event) {
            switch event {
            case let e as RosterModule.ItemUpdatedEvent:
                DispatchQueue.main.async {
                    self.controller?.rosterController?.updateItem(item: e.rosterItem!);
                }
            default:
                break;
            }
        }
        
    }
    
    enum ShareError: Error {
        case featureNotAvailable
        case tooBig
        case failure
        
    }
    
}
