//
// ChannelJoinViewController.swift
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
import TigaseSwift
import TigaseLogging

class ChannelJoinViewController: UITableViewController {
    
    @IBOutlet var joinButton: UIBarButtonItem!;
    
    @IBOutlet var nameField: UILabel!;
    @IBOutlet var jidField: UILabel!;
    @IBOutlet var nicknameField: UITextField!;
    @IBOutlet var passwordField: UITextField!;
    @IBOutlet var bookmarkCreateSwitch: UISwitch!;
    @IBOutlet var bookmarkAutojoinSwitch: UISwitch!;
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ChannelJoinViewController");
    
    var client: XMPPClient!;
    var channelJid: BareJID!;
    var name: String?;
    var componentType: ChannelsHelper.ComponentType = .mix;
    var passwordRequired: Bool = false;
    var action: Action = .join
    var password: String?;
    var nickname: String? = nil;
    

    var mixInvitation: MixInvitation? {
        didSet {
            if let value = mixInvitation {
                channelJid = value.channel;
                componentType = .mix;
                action = .join;
                name = value.channel.description;
            }
        }
    }
    
    var roomFeatures: [String]?;
    
    var fromBookmark: Bool = false;
    var onConversationJoined: ((Conversation)->Void)?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.tableView.contentInsetAdjustmentBehavior = .always;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.nameField.text = name;
        self.jidField.text = channelJid?.description;
        self.passwordField.text = password
        self.nicknameField.text = self.nickname ?? AccountManager.getAccount(for: self.client.userBareJid)?.nickname;
               
        bookmarkCreateSwitch.isOn = Settings.enableBookmarksSync;
        
        switch action {
        case .join:
            if componentType == .muc {
                operationStarted(message: NSLocalizedString("Checking…", comment: "channel join view operation label"));
                client.module(.disco).info(for: JID(channelJid), node: nil, completionHandler: { result in
                    switch result {
                    case .success(let info):
                        DispatchQueue.main.async {
                            if let name = info.identities.first?.name {
                                self.nameField.text = name;
                            }
                            self.roomFeatures = info.features;
                            self.passwordRequired = info.features.contains("muc_passwordprotected");
                            self.tableView.reloadData();
                            self.updateJoinButtonStatus();
                            self.operationEnded();
                        }
                    case .failure(_):
                        DispatchQueue.main.async {
                            self.roomFeatures = [];
                            self.updateJoinButtonStatus();
                            self.operationEnded();
                        }
                    }
                });
            } else {
                self.updateJoinButtonStatus();
            }
            joinButton.title = NSLocalizedString("Join", comment: "button label");
        default:
            joinButton.title = NSLocalizedString("Create", comment: "button label");
            updateJoinButtonStatus();
            break;
        }
    }
    
    @objc func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func joinClicked(_ sender: Any) {
        let nick = self.nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "";
        let password = (passwordField?.text?.isEmpty ?? true) ? nil : passwordField.text;
        guard !nick.isEmpty else {
            return;
        }
        
        switch action {
        case .join:
            self.join(nick: nick, password: password);
        case .create(let isPublic, let invitationOnly, let description, let avatar):
            self.create(name: name!, description: description, nick: nick, isPublic: isPublic, invitationOnly: invitationOnly, avatar: avatar);
        }
     }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if (!passwordRequired && section == 2) || ((fromBookmark || componentType == .mix) && section == 3) {
            return 0.1;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if (!passwordRequired && section == 2) || ((fromBookmark || componentType == .mix) && section == 3) {
            return 0;
        }
        return super.tableView(tableView, numberOfRowsInSection: section);
    }
        
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if (!passwordRequired && section == 2) || ((fromBookmark || componentType == .mix) && section == 3) {
            return 0.1;
        }
        return super.tableView(tableView, heightForFooterInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (!passwordRequired && section == 2) || ((fromBookmark || componentType == .mix) && section == 3) {
            return nil;
        }
        return super.tableView(tableView, titleForHeaderInSection: section);
    }
 
    func operationStarted(message: String) {
        self.tableView.refreshControl = UIRefreshControl();
        self.tableView.refreshControl?.attributedTitle = NSAttributedString(string: message);
        self.tableView.refreshControl?.isHidden = false;
        self.tableView.refreshControl?.layoutIfNeeded();
        self.tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y - self.tableView.refreshControl!.frame.height), animated: true)
        self.tableView.refreshControl?.beginRefreshing();
    }
    
    func operationEnded() {
        if let tableView = self.tableView {
            tableView.refreshControl?.endRefreshing();
            tableView.refreshControl = nil;
        }
    }
    
    @IBAction func textFieldChanged(_ sender: Any) {
        updateJoinButtonStatus();
    }
    
    @IBAction func bookmarkCreateChanged(_ sender: UISwitch) {
        bookmarkAutojoinSwitch.isEnabled = sender.isOn;
    }
    
    private func updateJoinButtonStatus() {
        let nick = self.nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "";
        self.joinButton.isEnabled = (!nick.isEmpty) && ((!passwordRequired) || (!(passwordField.text?.isEmpty ?? true)));
    }
    
    private func create(name: String, description: String?, nick: String, isPublic: Bool, invitationOnly: Bool, avatar: UIImage?) {
        let client = self.client!;
        switch componentType {
        case .mix:
            let mixModule = client.module(.mix);
            self.operationStarted(message: NSLocalizedString("Creating channel…", comment: "channel join view operation label"))
                
            Task {
                do {
                    let channelJid = try await mixModule.create(channel: channelJid.localPart, at: BareJID(domain: channelJid.domain));
                    do {
                        if invitationOnly {
                            _ = try await mixModule.changeAccessPolicy(of: channelJid, isPrivate: invitationOnly);
                        }
                        Task {
                            try await mixModule.info(MixChannelInfo(name: name, description: description, contact: []), for: channelJid);
                        }
                        Task {
                            if let pngImage = avatar?.scaled(maxWidthOrHeight: 48), let pngData = pngImage.pngData() {
                                var avatars: [PEPUserAvatarModule.Avatar] = [.init(data: pngData, mimeType: "image/png", width: Int(pngImage.size.width), height: Int(pngImage.size.height))];
                                if let jpegImage = avatar?.scaled(maxWidthOrHeight: 512), let jpegData = jpegImage.jpegData(compressionQuality: 0.8) {
                                    avatars.append(.init(data: jpegData, mimeType: "image/jpeg", width: Int(jpegImage.size.width), height: Int(jpegImage.size.height)));
                                }
                                _ = try await client.module(.pepUserAvatar).publishAvatar(at: channelJid, avatar: avatars);
                            }
                        }
                        _ = try await mixModule.join(channel: channelJid, withNick: nick);
                    } catch {
                        try? await mixModule.destroy(channel: channelJid);
                        throw error;
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.operationEnded();
                        self?.dismiss(animated: true, completion: nil);
                        if let channel = DBChatStore.instance.channel(for: client, with: channelJid) {
                            self?.onConversationJoined?(channel);
                        }
                    }
                } catch {
                    let err = error as? XMPPError ?? .undefined_condition;
                    DispatchQueue.main.async { [weak self] in
                        self?.operationEnded();
                        
                        guard let that = self else {
                            return;
                        };
                        let alert = UIAlertController(title: NSLocalizedString("Error occurred", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not create channel on the server. Got following error: %@", comment: "alert body"), err.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        that.present(alert, animated: true, completion: nil);
                    }
                }
            }
            break;
        case .muc:
            let mucModule = client.module(.muc);
            let priv = !isPublic;
            let roomName = isPublic ? channelJid.localPart! : UUID().uuidString;

            let createBookmark = bookmarkCreateSwitch.isOn;
            let autojoin = createBookmark && bookmarkAutojoinSwitch.isOn;
            
            let form = RoomConfig();
            form.FORM_TYPE = "http://jabber.org/protocol/muc#roomconfig";
            form.name = name;
            form.membersOnly = priv;
            form.publicRoom = !priv;
            form.whois = priv ? .anyone : .moderators;
            
            let mucServer = self.channelJid.domain;
            self.operationStarted(message: NSLocalizedString("Creating channel…", comment: "channel join view operation label"))
            Task {
                do {
                    try await mucModule.roomConfiguration(form, of: JID(BareJID(localPart: roomName, domain: mucServer)));
                    let r = try await mucModule.join(roomName: roomName, mucServer: mucServer, nickname: nick);
                    switch r {
                    case .created(let room), .joined(let room):
                        if createBookmark {
                            Task {
                                try await client.module(.pepBookmarks).addOrUpdate(bookmark: Bookmarks.Conference(name: name.isEmpty ? room.jid.localPart : name, jid: JID(room.jid), autojoin: autojoin, nick: nick, password: nil));
                            }
                        }
                        
                        var features = Set<Room.Feature>();
                        features.insert(.nonAnonymous);
                        if priv {
                            features.insert(.membersOnly);
                        }
                        (room as! Room).updateRoom(name: name);
                        (room as! Room).roomFeatures = features;
                        Task {
                            let vcard = VCard();
                            if let binval = avatar?.scaled(maxWidthOrHeight: 512.0)?.jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                                vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
                            }
                            try await client.module(.vcardTemp).publish(vcard: vcard, to: room.jid);
                        }
                        
                        if description != nil {
                            try? await mucModule.setRoomSubject(roomJid: room.jid, newSubject: description);
                        }
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.operationEnded();
                            self?.dismiss(animated: true, completion: nil);
                            self?.onConversationJoined?(room as! Room);
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.operationEnded();
                        let alert = UIAlertController(title: NSLocalizedString("Error occurred", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not create channel on the server. Got following error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self.present(alert, animated: true, completion: nil);
                    }
                }
            }
        }
    }
    
    private func join(nick: String, password: String?) {
        let client = self.client!;
        guard (!passwordRequired) || (password != nil) else {
            return;
        }
        
        switch componentType {
        case .mix:
            self.operationStarted(message: NSLocalizedString("Joining…", comment: "channel join view operation label"));
            Task {
                do {
                    defer {
                        DispatchQueue.main.async { [weak self] in
                            self?.operationEnded();
                        }
                    }
                    _ = try await client.module(.mix).join(channel: channelJid, withNick: nick, invitation: mixInvitation);
                    DispatchQueue.main.async {
                        self.dismiss(animated: true, completion: nil);
                        if let channel = DBChatStore.instance.channel(for: client, with: self.channelJid) {
                            self.onConversationJoined?(channel);
                        }
                    }

                } catch {
                    DispatchQueue.main.async { [weak self] in
                        let alert = UIAlertController(title: NSLocalizedString("Could not join", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert button"), error.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }

                }
            }
        case .muc:
            let room = channelJid!;
            let createBookmark = bookmarkCreateSwitch.isOn;
            let autojoin = createBookmark && bookmarkAutojoinSwitch.isOn;
            
            self.operationStarted(message: NSLocalizedString("Joining…", comment: "channel join view operation label"));
            Task {
                do {
                    let joinResult = try await client.module(.muc).join(roomName: room.localPart!, mucServer: room.domain, nickname: nick, password: password);
                    DispatchQueue.main.async {
                        self.operationEnded();
                    }
                    switch joinResult {
                    case .created(let room), .joined(let room):
                        let info = try await client.module(.disco).info(for: JID(room.jid));
                        if createBookmark {
                            client.module(.pepBookmarks).addOrUpdate(bookmark: Bookmarks.Conference(name: info.identities.first?.name ?? room.jid.localPart, jid: JID(room.jid), autojoin: autojoin, nick: nick, password: password), completionHandler: { _ in });
                        }
                        (room as! Room).updateRoom(name: info.identities.first(where: { $0.category == "conference" })?.name?.trimmingCharacters(in: .whitespacesAndNewlines))
                        (room as! Room).roomFeatures = Set(info.features.compactMap({ Room.Feature(rawValue: $0) }));
                        Task {
                            do {
                                _ = try await (room as! Room).registerForTigasePushNotification(true);
                            } catch {
                                self.logger.error("failed to enable push for: \(room.jid), result: \(error.localizedDescription)");
                            }
                        }
                        DispatchQueue.main.async {
                            self.onConversationJoined?(room as! Room);
                        }
                    }
                    DispatchQueue.main.async {
                        self.dismiss(animated: true, completion: nil);
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.operationEnded();
                        let alert = UIAlertController(title: NSLocalizedString("Could not join", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert button"), error.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }
                }
            }
        }
    }
    
    enum Action {
        case create(isPublic: Bool, invitationOnly: Bool, description: String?, avatar: UIImage?)
        case join
    }
}
