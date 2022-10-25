//
// ShareViewController.swift
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
import Social
import Shared
import Martin
import TigaseSQLite3
import MobileCoreServices
import Combine

extension Query {
    
    static let selectRosterItems = Query("SELECT ri.account, ri.jid, ri.name, ri.data FROM roster_items ri");
    static let selectAvatars = Query("select ac.account, ac.jid, ac.type, ac.hash FROM avatars_cache ac");
    
}

struct RosterItem: Equatable {
    let account: BareJID;
    let jid: BareJID;
    let name: String?;
    
    var displayName: String {
        return name ?? jid.description;
    }
    
    var initials: String? {
        let parts = displayName.uppercased().components(separatedBy: CharacterSet.letters.inverted);
        let first = parts.first?.first;
        let last = parts.count > 1 ? parts.last?.first : nil;
        return (last == nil || first == nil) ? (first == nil ? nil : "\(first!)") : "\(first!)\(last!)";
    }
}

struct DBRosterData: Codable, DatabaseConvertibleStringValue {
    
    let groups: [String];
    let annotations: [RosterItemAnnotation];
        
}

class ShareViewController: UITableViewController {
    
    var recipients: [RosterItem] = [];
    
    var sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share");
    
    var rosterItems: [RosterItem] = [];
    
    private let avatarStore = AvatarStore();
    
    var imageQuality: ImageQuality {
        if let valueStr = sharedDefaults?.string(forKey: "imageQuality"), let value = ImageQuality(rawValue: valueStr) {
            return value;
        }
        return .medium;
    }

    var videoQuality: VideoQuality {
        if let valueStr = sharedDefaults?.string(forKey: "videoQuality"), let value = VideoQuality(rawValue: valueStr) {
            return value;
        }
        return .medium;
    }

    override func viewDidLoad() {
        try! AccountManager.initialize();
        
        super.viewDidLoad();
        
        self.navigationItem.title = NSLocalizedString("Select recipients", comment: "view title");
        self.navigationItem.setLeftBarButton(UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped(_:))), animated: false);
        self.navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:))), animated: false)
        self.navigationItem.rightBarButtonItem?.isEnabled = false;
        
        let dbUrl = Database.mainDatabaseUrl();

        if !FileManager.default.fileExists(atPath: dbUrl.path) {
            let controller = UIAlertController(title: NSLocalizedString("Please launch application from the home screen before continuing.", comment: "alert title"), message: nil, preferredStyle: .alert);
            controller.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .destructive, handler: { (action) in
                self.extensionContext?.cancelRequest(withError: ShareError.unknownError);
            }))
            self.present(controller, animated: true, completion: nil);
        }
        
        let accounts = Set(AccountManager.activeAccounts().map({ $0.name }));
        rosterItems = try! Database.main.reader({ database in
            try! database.select(query: .selectRosterItems, cached: false, params: []).mapAll({ c -> RosterItem? in
                guard let account = c.bareJid(for: "account"), accounts.contains(account), let jid = c.bareJid(for: "jid") else {
                    return nil;
                }
                
                if let data: DBRosterData = c.object(for: "data") {
                    guard data.annotations.isEmpty else {
                        return nil;
                    }
                }
                
                return RosterItem(account: account, jid: jid, name: c.string(for: "name"));
            })
        }).sorted(by: { r1, r2 -> Bool in
            return r1.displayName.lowercased() < r2.displayName.lowercased();
        })
        
        for url in try! FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            try? FileManager.default.removeItem(at: url);
        }
    }
    
    private var alertController: UIAlertController?;
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);
        if !sharedDefaults!.bool(forKey: "SharingViaHttpUpload") {
            var error = true;
            if let provider = (self.extensionContext!.inputItems.first as? NSExtensionItem)?.attachments?.first {
                error = !provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String);
            }
            if error {
                self.showAlert(title: NSLocalizedString("Failure", comment: "alert title"), message: NSLocalizedString("Sharing feature with HTTP upload is disabled within application. To use this feature you need to enable sharing with HTTP upload in application", comment: "alert body"));
            }
        }
    }
    
    @objc func cancelTapped(_ sender: Any) {
        let error = NSError(domain: "tigase.siskinim", code: 0, userInfo: [:]);
        self.extensionContext?.cancelRequest(withError: error);
    }
    
    private var cancelled = false;
//    private var clients: [XMPPClient] = [];
    
    @objc func doneTapped(_ sender: Any) {
        self.navigationItem.rightBarButtonItem?.isEnabled = false;
        alertController = UIAlertController(title: "", message: nil, preferredStyle: .alert);
        let activityIndicator = UIActivityIndicatorView(style: .medium);
        activityIndicator.startAnimating();
        let label = UILabel(frame: .zero);
        label.text = NSLocalizedString("Preparing…", comment: "operation label");
        let stack = UIStackView(arrangedSubviews: [activityIndicator, label]);
        stack.alignment = .center;
        stack.distribution = .fillProportionally;
        stack.axis = .horizontal;
        stack.translatesAutoresizingMaskIntoConstraints = false;
        stack.spacing = 14;
        alertController?.view.addSubview(stack);
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: alertController!.view.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: alertController!.view.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: alertController!.view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: alertController!.view.bottomAnchor, constant: -60)
        ])
        alertController?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
            self.cancelled = true;
            Task {
                for task in self.clients.values {
                    task.cancel()
                }
                await MainActor.run(body: {
                    self.extensionContext?.cancelRequest(withError: ShareError.unknownError);
                })
            }
        }));
        self.present(alertController!, animated: true, completion: nil);

        Task {
            do {
                let attachment = try await extractAttachments();
                await MainActor.run(body: {
                    label.text = NSLocalizedString("Sending…", comment: "operation label");
                })
                let errors = await share(attachment: attachment);
                if cancelled, case let .file(url, _) = attachment {
                    try? FileManager.default.removeItem(at: url);
                }
                
                DispatchQueue.main.async {
                    self.alertController?.dismiss(animated: true, completion: {
                        self.navigationItem.rightBarButtonItem?.isEnabled = true;
                        guard let error = errors.first?.error else {
                            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil);
                            return;
                        }
                        self.show(error: error);
                    });
                }
            } catch {
                await MainActor.run(body: {
                    self.alertController?.dismiss(animated: true, completion: {
                        self.navigationItem.rightBarButtonItem?.isEnabled = true;
                        self.show(error: error);
                    })
                })
            }
        }
    }
    
    private struct ErrorResult {
        let jid: BareJID;
        let error: Error;
    }
    
    private var clients: [BareJID: Task<XMPPClient,Error>] = [:];
    private let clientsLock = UnfairLock();
    
    private func client(account: BareJID) async throws -> XMPPClient {
        let task: Task<XMPPClient,Error> = clientsLock.with {
            guard let task = clients[account] else {
                let task: Task<XMPPClient,Error> = Task {
                    guard let config = AccountManager.account(for: account) else {
                        throw XMPPError(condition: .not_authorized);
                    }
                    let client = self.createXmppClient(for: account);
                    client.configure(for: config);
                    client.connectionConfiguration.resource = UUID().uuidString;
                    do {
                        try await client.loginAndWait(lastSeeOtherHost: config.lastEndpoint);
                    } catch {
                        if config.lastEndpoint != nil {
                            try await client.loginAndWait();
                        } else {
                            throw error;
                        }
                    }
                    try Task.checkCancellation()
                    return client;
                }
                clients[account] = task;
                return task;
            }
            return task;
        }
        return try await task.value;
    }
    
    private var attachmentUpload: [BareJID: Task<URL,Error>] = [:];
    
    private func prepareAttachment(_ attachment: Attachment, for account: BareJID) async throws -> (String, String?) {
        switch attachment {
        case .file(let tempUrl, let fileInfo):
            let task: Task<URL,Error> = clientsLock.with({
                guard let task = attachmentUpload[account] else {
                    let task: Task<URL,Error> = Task {
                        let client = try await self.client(account: account);
                        let result = try await upload(file: tempUrl, fileInfo: fileInfo, using: client);
                        try Task.checkCancellation()
                        return result;
                    }
                    attachmentUpload[account] = task;
                    return task;
                }
                return task;
            })
            let url = try await task.value;
            return (url.absoluteString, url.absoluteString);
        case .link(let url):
            return (url.absoluteString, nil)
        case .text(let string):
            return (string, nil);
        }
    }
    
    private func share(attachment: Attachment) async -> [ErrorResult] {
        return await withTaskGroup(of: ErrorResult?.self, returning: [ErrorResult].self, body: { group in
            for recipient in recipients {
                group.addTask {
                    do {
                        let client = try await self.client(account: recipient.account);
                        let (body, oob) = try await self.prepareAttachment(attachment, for: recipient.account);
                        try await self.send(using: client, to: recipient, body: body, oob: oob);
                        return nil;
                    } catch {
                        return ErrorResult(jid: recipient.jid, error: error);
                    }
                }
            }
            
            return await group.reduce(into: [ErrorResult](), { if let err = $1 { $0.append(err) } });
        })
    }
        
    private func send(using client: XMPPClient, to recipient: RosterItem, body: String?, oob: String?) async throws {
        let message = Message(element: Element(name: "message"));
        message.type = .chat;
        message.to = JID(recipient.jid)
        message.id = UUID().uuidString;
        message.body = body;
        message.oob = oob;
        try await client.writer.write(stanza: message);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rosterItems.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "recipientTableViewCell", for: indexPath);
        let item = rosterItems[indexPath.row];
        cell.imageView?.image = avatar(for: item) ?? generateAvatar(for: item);
        cell.imageView?.layer.cornerRadius = 20;
        cell.imageView?.layer.masksToBounds = true;
        cell.textLabel?.text = item.displayName;
        cell.detailTextLabel?.text = item.jid.description;
        if recipients.contains(item) {
            cell.accessoryType = .checkmark;
        } else {
            cell.accessoryType = .none;
        }
        return cell;
    }
    
    func avatar(for item: RosterItem) -> UIImage? {
        guard let hash = avatarStore.avatarHash(for: item.jid, on: item.account).sorted().first else {
            return nil;
        }

        return avatarStore.avatar(for: hash.hash)?.scaled(maxWidthOrHeight: 40);
    }
    
    func generateAvatar(for item: RosterItem) -> UIImage? {
        guard let initials = item.initials else {
            return nil;
        }
        
        let scale = UIScreen.main.scale;
        let size = CGSize(width: 40, height: 40);
        UIGraphicsBeginImageContextWithOptions(size, false, scale);
        let ctx = UIGraphicsGetCurrentContext()!;
        let path = CGPath(ellipseIn: CGRect(origin: .zero, size: size), transform: nil);
        ctx.addPath(path);
                
        let colors = [UIColor.systemGray.adjust(brightness: 0.52).cgColor, UIColor.systemGray.adjust(brightness: 0.48).cgColor];
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!;
        ctx.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: 0, y: size.height), options: []);
        
        let textAttr: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white.withAlphaComponent(0.9), .font: UIFont.systemFont(ofSize: size.width * 0.4, weight: .medium)];
        let textSize = initials.size(withAttributes: textAttr);
        
        initials.draw(in: CGRect(x: size.width/2 - textSize.width/2, y: size.height/2 - textSize.height/2, width: textSize.width, height: textSize.height), withAttributes: textAttr);
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        
        return image;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = rosterItems[indexPath.row];
        if let idx = recipients.firstIndex(of: item) {
            recipients.remove(at: idx);
        } else {
            recipients.append(item);
        }
        self.navigationItem.rightBarButtonItem?.isEnabled = !recipients.isEmpty;
        tableView.reloadData();
    }
    
    private func createXmppClient(for account: BareJID) -> XMPPClient {
        let client = XMPPClient();

        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            options.connectionTimeout = 15;
        })
        client.connectionConfiguration.userJid = account;

        _ = client.modulesManager.register(AuthModule());
        _ = client.modulesManager.register(StreamFeaturesModule());
        _ = client.modulesManager.register(SaslModule());
        _ = client.modulesManager.register(ResourceBinderModule());
        _ = client.modulesManager.register(SessionEstablishmentModule());
        _ = client.modulesManager.register(DiscoveryModule());
        client.modulesManager.register(PresenceModule()).initialPresence = false;
        _ = client.modulesManager.register(HttpFileUploadModule());

        return client;
    }
    
    private func upload(file localUrl: URL, fileInfo: ShareFileInfo, using client: XMPPClient) async throws -> URL {
        let uti = try? localUrl.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier;
        let mimeType = uti != nil ? (UTTypeCopyPreferredTagWithClass(uti! as CFString, kUTTagClassMIMEType)?.takeRetainedValue() as String?) : nil;
        let size = try! FileManager.default.attributesOfItem(atPath: localUrl.path)[FileAttributeKey.size] as! UInt64;
      
        guard let data = try? Data(contentsOf: localUrl) else {
            throw ShareError.noAccessError;
        }

        return try await HTTPFileUploadHelper.upload(for: client, filename: fileInfo.filenameWithSuffix, data: data, filesize: Int(size), mimeType: mimeType ?? "application/octet-stream", delegate: nil);
    }
    
    enum Attachment {
        case file(URL, ShareFileInfo)
        case link(URL)
        case text(String)
    }
    
    private func extractAttachments() async throws -> Attachment {
        return try await withUnsafeThrowingContinuation({ continuation in
            extractAttachments(completionHandler: continuation.resume(with:));
        })
    }
    
    private func extractAttachments(completionHandler: @escaping (Result<Attachment,Error>)->Void) {
        if let provider = (self.extensionContext?.inputItems.first as? NSExtensionItem)?.attachments?.first {
            if provider.hasItemConformingToTypeIdentifier(kUTTypeVideo as String) {
                provider.loadFileRepresentation(forTypeIdentifier: kUTTypeVideo as String, completionHandler: { url, error in
                    guard let url = url else {
                        completionHandler(.failure(error!));
                        return;
                    }
                    do {
                        let localUrl = try self.copyFileLocally(url: url);
                        Task {
                            defer {
                                try? FileManager.default.removeItem(at: localUrl);
                            }
                            do {
                                let (url,fileInfo) = try await MediaHelper.compressMovie(url: localUrl, fileInfo: ShareFileInfo.from(url: url, defaultSuffix: "mov"), quality: self.videoQuality, progressCallback: { _ in });
                                completionHandler(.success(.file(url, fileInfo)));
                            } catch {
                                completionHandler(.failure(error));
                            }
                        }
                    } catch {
                        completionHandler(.failure(error))
                    }
                });
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                provider.loadFileRepresentation(forTypeIdentifier: kUTTypeImage as String, completionHandler: { url, error in
                    guard let url = url else {
                        completionHandler(.failure(error!));
                        return;
                    }
                    do {
                        let localUrl = try self.copyFileLocally(url: url);
                        Task {
                            defer {
                                try? FileManager.default.removeItem(at: localUrl);
                            }
                            do {
                                let (url,fileInfo) = try MediaHelper.compressImage(url: localUrl, fileInfo: ShareFileInfo.from(url: url, defaultSuffix: "jpg"), quality: self.imageQuality);
                                completionHandler(.success(.file(url, fileInfo)));
                            } catch {
                                completionHandler(.failure(error));
                            }
                        }
                    } catch {
                        completionHandler(.failure(error))
                    }
                });
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String) {
                provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil, completionHandler: { (item, error) in
                    guard let url = item as? URL else {
                        completionHandler(.failure(error!));
                        return;
                    }
                    do {
                        let localUrl = try self.copyFileLocally(url: url);
                        completionHandler(.success(.file(localUrl, ShareFileInfo.from(url: url, defaultSuffix: nil))));
                    } catch {
                        completionHandler(.failure(error));
                    }
                });
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil, completionHandler: { (item, error) in
                    guard let url = item as? URL else {
                        completionHandler(.failure(error!));
                        return;
                    }
                    completionHandler(.success(.link(url)));
                })
            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeText as String) {
                provider.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil, completionHandler: { (item, error) in
                    guard let text = item as? String else {
                        completionHandler(.failure(error!));
                        return;
                    }
                    completionHandler(.success(.text(text)));
                })
            } else {
                completionHandler(.failure(ShareError.notSupported));
            }
        } else {
            completionHandler(.failure(ShareError.noAccessError));
        }
    }
        
    private func copyFileLocally(url: URL) throws -> URL {
        let filename = url.lastPathComponent;
        var suffix: String = "";
        if let idx = filename.lastIndex(of: ".") {
            suffix = String(filename.suffix(from: idx));
        }
        
        let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + suffix, isDirectory: false);
        try FileManager.default.copyItem(at: url, to: tmpUrl);
        return tmpUrl;
    }
    
    func show(error: Error) {
        showAlert(title: NSLocalizedString("Failure", comment: "alert title"), message: (error as? ShareError)?.message ?? error.localizedDescription);
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: {(action) in
                self.extensionContext?.cancelRequest(withError: ShareError.unknownError);
            }));
            self.present(alert, animated: true, completion: nil);
        }
    }

//    func getActiveAccounts() -> [BareJID] {
//        var accounts = [BareJID]();
//        let query = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitAll, String(kSecReturnAttributes) : kCFBooleanTrue as Any, String(kSecAttrService) : "xmpp" ] as [String : Any];
//        var result:AnyObject?;
//
//        let lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
//            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
//        }
//
//        if lastResultCode == noErr {
//            if let results = result as? [[String:NSObject]] {
//                for r in results {
//                    if let name = r[String(kSecAttrAccount)] as? String {
//                        if let data = r[String(kSecAttrGeneric)] as? NSData {
//                            NSKeyedUnarchiver.setClass(ServerCertificateInfoOld.self, forClassName: "Siskin.ServerCertificateInfo");
//                            let dict = NSKeyedUnarchiver.unarchiveObject(with: data as Data) as? [String:AnyObject];
//                            if dict!["active"] as? Bool ?? false {
//                                accounts.append(BareJID(name));
//                            }
//                        }
//                    }
//                }
//            }
//
//        }
//        return accounts;
//    }
//
//    func getAccountPassword(for account: BareJID) -> String? {
//        let query: [String: NSObject] = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(kSecReturnData) : kCFBooleanTrue, String(kSecAttrService) : "xmpp" as NSObject, String(kSecAttrAccount) : account.description as NSObject ];
//
//        var result:AnyObject?;
//
//        let lastResultCode: OSStatus = withUnsafeMutablePointer(to: &result) {
//            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0));
//        }
//
//        if lastResultCode == noErr {
//            if let data = result as? NSData {
//                return String(data: data as Data, encoding: String.Encoding.utf8);
//            }
//        }
//        return nil;
//    }
    
}
