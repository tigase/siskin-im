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
import Martin
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
                name = value.channel.stringValue;
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
        self.jidField.text = channelJid?.stringValue;
        self.passwordField.text = password
        self.nicknameField.text = self.nickname ?? AccountManager.getAccount(for: self.client.userBareJid)?.nickname;
               
        bookmarkCreateSwitch.isOn = Settings.enableBookmarksSync;
        
        switch action {
        case .join:
            if componentType == .muc {
                operationStarted(message: NSLocalizedString("Checking…", comment: "channel join view operation label"));
                client.module(.disco).getInfo(for: JID(channelJid), node: nil, completionHandler: { result in
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
                
            mixModule.create(channel: channelJid.localPart, at: BareJID(domain: channelJid.domain), completionHandler: { [weak self] result in
                switch result {
                case .success(let channelJid):
                        mixModule.join(channel: channelJid, withNick: nick, completionHandler: { result in
                            DispatchQueue.main.async {
                                self?.operationEnded();
                            }
                            switch result {
                            case .success(_):
                                DispatchQueue.main.async {
                                    self?.dismiss(animated: true, completion: nil);
                                    if let channel = DBChatStore.instance.channel(for: client, with: channelJid) {
                                        self?.onConversationJoined?(channel);
                                    }
                                }
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    guard let that = self else {
                                        return;
                                    }
                                    let alert = UIAlertController(title: NSLocalizedString("Error occurred", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not join newly created channel '%@' on the server. Got following error: %@", comment: "alert body"), channelJid.stringValue, error.localizedDescription), preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                                    that.present(alert, animated: true, completion: nil);
                                }
                            }
                        })
                        mixModule.publishInfo(for: channelJid, info: ChannelInfo(name: name, description: description, contact: []), completionHandler: nil);
                        if let avatarData = avatar?.scaled(maxWidthOrHeight: 512.0)?.jpegData(compressionQuality: 0.8) {
                            client.module(.pepUserAvatar).publishAvatar(at: channelJid, data: avatarData, mimeType: "image/jpeg", completionHandler: { result in
                                self?.logger.debug("avatar publication result: \(result)");
                            });
                        }
                        if invitationOnly {
                            mixModule.changeAccessPolicy(of: channelJid, isPrivate: invitationOnly, completionHandler: { result in
                                self?.logger.debug("changed channel access policy: \(result)");
                            })
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self?.operationEnded();
                            guard let that = self else {
                                return;
                            }
                            let alert = UIAlertController(title: NSLocalizedString("Error occurred", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not create channel on the server. Got following error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                            that.present(alert, animated: true, completion: nil);
                        }
                    }
                })
                break;
        case .muc:
            let mucModule = client.module(.muc);
            let priv = !isPublic;
            let roomName = isPublic ? channelJid.localPart! : UUID().uuidString;

            let createBookmark = bookmarkCreateSwitch.isOn;
            let autojoin = createBookmark && bookmarkAutojoinSwitch.isOn;
            
            let form = JabberDataElement(type: .submit);
            form.addField(HiddenField(name: "FORM_TYPE")).value = "http://jabber.org/protocol/muc#roomconfig";
            form.addField(TextSingleField(name: "muc#roomconfig_roomname", value: name));
            form.addField(BooleanField(name: "muc#roomconfig_membersonly", value: priv));
            form.addField(BooleanField(name: "muc#roomconfig_publicroom", value: !priv));
//            form.addField(TextSingleField(name: "muc#roomconfig_roomdesc", value: channelDescription));
            form.addField(TextSingleField(name: "muc#roomconfig_whois", value: priv ? "anyone" : "moderators"))
            let mucServer = self.channelJid.domain;
            self.operationStarted(message: NSLocalizedString("Creating channel…", comment: "channel join view operation label"))
            mucModule.setRoomConfiguration(roomJid: JID(BareJID(localPart: roomName, domain: mucServer)), configuration: form, completionHandler: { [weak self] configResult in
                mucModule.join(roomName: roomName, mucServer: mucServer, nickname: nick).handle({ [weak self] joinResult in
                    switch joinResult {
                    case .success(let r):
                        switch r {
                        case .created(let room), .joined(let room):
                            if createBookmark {
                                client.module(.pepBookmarks).addOrUpdate(bookmark: Bookmarks.Conference(name: name.isEmpty ? room.jid.localPart : name, jid: JID(room.jid), autojoin: autojoin, nick: nick, password: nil));
                            }
                            
                            var features = Set<Room.Feature>();
                            features.insert(.nonAnonymous);
                            if priv {
                                features.insert(.membersOnly);
                            }
                            (room as! Room).roomFeatures = features;
                            let vcard = VCard();
                            if let binval = avatar?.scaled(maxWidthOrHeight: 512.0)?.jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                                vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
                            }
                            client.module(.vcardTemp).publishVCard(vcard, to: room.jid, completionHandler: nil);
                            if description != nil {
                                mucModule.setRoomSubject(roomJid: room.jid, newSubject: description);
                            }
                            
                            let finished = {
                                DispatchQueue.main.async {
                                    self?.operationEnded();
                                    self?.dismiss(animated: true, completion: nil);
                                    self?.onConversationJoined?(room as! Room);
                                }
                            }
                            switch configResult {
                            case .success(_):
                                finished();
                            case .failure(_):
                                mucModule.setRoomConfiguration(roomJid: JID(room.jid), configuration: form, completionHandler: { configResult in
                                    switch configResult {
                                    case .failure(let error):
                                        DispatchQueue.main.async {
                                            self?.operationEnded();
                                            guard let that = self else {
                                                return;
                                            }
                                            let alert = UIAlertController(title: NSLocalizedString("Error occurred", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Room was created and joined but room was not properly configured. Got following error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                                            alert.addAction(UIAlertAction(title: NSLocalizedString("Destroy", comment: "button label"), style: .destructive, handler: { _ in
                                                room.context?.module(.muc).destroy(room: room);
                                                finished();
                                            }))
                                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                                                finished();
                                            }));
                                            that.present(alert, animated: true, completion: nil);
                                        }
                                    case .success(_):
                                        finished();
                                    }
                                })
                            }
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self?.operationEnded();
                            guard let that = self else {
                                return;
                            }
                            let alert = UIAlertController(title: NSLocalizedString("Error occurred", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not create channel on the server. Got following error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                            that.present(alert, animated: true, completion: nil);
                        }                        }
                })
            })
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
            client.module(.mix).join(channel: channelJid, withNick: nick, invitation: mixInvitation, completionHandler: { result in
                switch result {
                case .success(_):
                    // we have joined, so all what we need to do is close this window
                    DispatchQueue.main.async {
                        self.operationEnded();
                        self.dismiss(animated: true, completion: nil);
                        if let channel = DBChatStore.instance.channel(for: client, with: self.channelJid) {
                            self.onConversationJoined?(channel);
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { [weak self] in
                        self?.operationEnded();
                        let alert = UIAlertController(title: NSLocalizedString("Could not join", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert button"), error.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }
                }
             });
        case .muc:
            let room = channelJid!;
            let createBookmark = bookmarkCreateSwitch.isOn;
            let autojoin = createBookmark && bookmarkAutojoinSwitch.isOn;
            
            self.operationStarted(message: NSLocalizedString("Joining…", comment: "channel join view operation label"));
            client.module(.muc).join(roomName: room.localPart!, mucServer: room.domain, nickname: nick, password: password).handle({ result in
                switch result {
                case .success(let joinResult):
                    DispatchQueue.main.async {
                        self.operationEnded();
                    }
                    switch joinResult {
                    case .created(let room), .joined(let room):
                        client.module(.disco).getInfo(for: JID(room.jid), completionHandler: { result in
                            switch result {
                            case .success(let info):
                                if createBookmark {
                                    client.module(.pepBookmarks).addOrUpdate(bookmark: Bookmarks.Conference(name: info.identities.first?.name ?? room.jid.localPart, jid: JID(room.jid), autojoin: autojoin, nick: nick, password: password));
                                }
                                (room as! Room).roomFeatures = Set(info.features.compactMap({ Room.Feature(rawValue: $0) }));
                            case .failure(_):
                                break;
                            }
                        });
                        (room as! Room).registerForTigasePushNotification(true, completionHandler: { (result) in
                            self.logger.debug("automatically enabled push for: \(room.jid), result: \(result)");
                        })
                        defer {
                            DispatchQueue.main.async {                                
                                self.onConversationJoined?(room as! Room);
                            }
                        }
                    }
                    if createBookmark {
                        client.module(.pepBookmarks).addOrUpdate(bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: autojoin, nick: nick, password: password));
                    }
                    DispatchQueue.main.async {
                        self.dismiss(animated: true, completion: nil);
                    }
                case .failure(let error):
                    DispatchQueue.main.async { [weak self] in
                        self?.operationEnded();
                        let alert = UIAlertController(title: NSLocalizedString("Could not join", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert button"), error.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }
                }
            });
        }
    }
    
    enum Action {
        case create(isPublic: Bool, invitationOnly: Bool, description: String?, avatar: UIImage?)
        case join
    }
}
