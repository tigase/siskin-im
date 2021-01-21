//
// MucChatViewController.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwiftOMEMO

class MucChatViewController: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar {

    static let MENTION_OCCUPANT = Notification.Name("groupchatMentionOccupant");
    
    var titleView: MucTitleView? {
        get {
            return self.navigationItem.titleView as? MucTitleView;
        }
    }
    var room: DBRoom? {
        get {
            return self.chat as? DBRoom;
        }
        set {
            self.chat = newValue;
        }
    }

    let log: Logger = Logger();

    override func viewDidLoad() {
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        let mucModule: MucModule? = XmppService.instance.getClient(forJid: account)?.modulesManager?.getModule(MucModule.ID);
        room = mucModule?.roomsManager.getRoom(for: jid) as? DBRoom;
        super.viewDidLoad()
        navigationItem.title = room?.name ?? jid.stringValue;
        
        titleView?.name = navigationItem.title;
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(MucChatViewController.roomInfoClicked));
        self.titleView?.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);
        
        initializeSharing();
        
        NotificationCenter.default.addObserver(self, selector: #selector(MucChatViewController.roomStatusChanged), name: MucEventHandler.ROOM_NAME_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(MucChatViewController.roomStatusChanged), name: MucEventHandler.ROOM_STATUS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(MucChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil)

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        self.updateTitleView();
        refreshRoomInfo(room!);
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let dbItem = dataSource.getItem(at: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewMessageCell", for: indexPath);
        }
        
        var continuation = false;
        if (indexPath.row + 1) < dataSource.count {
            if let prevItem = dataSource.getItem(at:  indexPath.row + 1) {
                continuation = dbItem.isMergeable(with: prevItem);
            }
        }
        
        switch dbItem {
        case let item as ChatMessage:
            if item.message.starts(with: "/me ") {
                let cell = tableView.dequeueReusableCell(withIdentifier: "ChatTableViewMeCell", for: indexPath) as! ChatTableViewMeCell;
                cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
                let name = item.authorNickname ?? item.jid.stringValue;
                cell.set(item: item, nickname: name);
                return cell;
            } else {
                let id = continuation ? "ChatTableViewMessageContinuationCell" : "ChatTableViewMessageCell";
                
                let cell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
                cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
                //        cell.nicknameLabel?.text = item.nickname;
                if cell.avatarView != nil {
                    if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account, let avatar = AvatarManager.instance.avatar(for: senderJid, on: item.account) {
                        cell.avatarView?.set(name: item.authorNickname, avatar: avatar, orDefault: AvatarManager.instance.defaultAvatar);
                    } else if let nickname = item.authorNickname, let photoHash = self.room?.presences[nickname]?.presence.vcardTempPhoto {
                        cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(withHash: photoHash), orDefault: AvatarManager.instance.defaultAvatar);
                    } else {
                        cell.avatarView?.set(name: item.authorNickname, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                    }
                }
                let sender = item.authorNickname ?? "From \(item.jid.stringValue)";
                if let author = item.authorNickname, let recipient = item.recipientNickname {
                    let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(author) " : "To \(recipient)  ");
                    var attrs: [NSAttributedString.Key : Any] = [:];
                    if let origFontSize = cell.nicknameView?.font?.pointSize {
                        attrs[.font] = UIFont.italicSystemFont(ofSize: origFontSize - 2);
                    }
                    if let color = UIColor(named: "chatMessageText") {
                        attrs[.foregroundColor] = color;
                    }
                    val.append(NSAttributedString(string: " (private message)", attributes: attrs));
                    
                    cell.nicknameView?.attributedText = val;
                } else {
                    cell.nicknameView?.text = sender;
                }
                
                cell.set(message: item);
                return cell;
            }
        case let item as ChatAttachment:
            let id = continuation ? "ChatTableViewAttachmentContinuationCell" : "ChatTableViewAttachmentCell";
            let cell: AttachmentChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! AttachmentChatTableViewCell;
            cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            if cell.avatarView != nil {
                if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account, let avatar = AvatarManager.instance.avatar(for: senderJid, on: item.account) {
                    cell.avatarView?.set(name: item.authorNickname, avatar: avatar, orDefault: AvatarManager.instance.defaultAvatar);
                } else if let nickname = item.authorNickname, let photoHash = self.room?.presences[nickname]?.presence.vcardTempPhoto {
                        cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(withHash: photoHash), orDefault: AvatarManager.instance.defaultAvatar);
                } else {
                    cell.avatarView?.set(name: item.authorNickname, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                }
            }
            let sender = item.authorNickname ?? "From \(item.jid.stringValue)";
            if let author = item.authorNickname, let recipient = item.recipientNickname {
                let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(author) " : "To \(recipient)  ");
                var attrs: [NSAttributedString.Key : Any] = [:];
                if let origFontSize = cell.nicknameView?.font?.pointSize {
                    attrs[.font] = UIFont.italicSystemFont(ofSize: origFontSize - 2);
                }
                if let color = UIColor(named: "chatMessageText") {
                    attrs[.foregroundColor] = color;
                }
                val.append(NSAttributedString(string: " (private message)", attributes: attrs));

                cell.nicknameView?.attributedText = val;
            } else {
                cell.nicknameView?.text = sender;
            }

            cell.set(attachment: item);
            cell.setNeedsUpdateConstraints();
            cell.updateConstraintsIfNeeded();
                
            return cell;
        case let item as ChatLinkPreview:
            let id = "ChatTableViewLinkPreviewCell";
            let cell: LinkPreviewChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! LinkPreviewChatTableViewCell;
            cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            cell.set(linkPreview: item);
            return cell;
        case let item as SystemMessage:
            let cell: ChatTableViewSystemCell = tableView.dequeueReusableCell(withIdentifier: "ChatTableViewSystemCell", for: indexPath) as! ChatTableViewSystemCell;
            cell.set(item: item);
            cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            return cell;
        case let item as ChatInvitation:
            let id = "ChatTableViewInvitationCell";
            let cell: InvitationChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! InvitationChatTableViewCell;
            cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            if cell.avatarView != nil {
                if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account, let avatar = AvatarManager.instance.avatar(for: senderJid, on: item.account) {
                    cell.avatarView?.set(name: item.authorNickname, avatar: avatar, orDefault: AvatarManager.instance.defaultAvatar);
                } else if let nickname = item.authorNickname, let photoHash = self.room?.presences[nickname]?.presence.vcardTempPhoto {
                        cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(withHash: photoHash), orDefault: AvatarManager.instance.defaultAvatar);
                } else {
                    cell.avatarView?.set(name: item.authorNickname, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                }
            }
            let sender = item.authorNickname ?? "From \(item.jid.stringValue)";
            if let author = item.authorNickname, let recipient = item.recipientNickname {
                let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(author) " : "To \(recipient)  ");
                var attrs: [NSAttributedString.Key : Any] = [:];
                if let origFontSize = cell.nicknameView?.font?.pointSize {
                    attrs[.font] = UIFont.italicSystemFont(ofSize: origFontSize - 2);
                }
                if let color = UIColor(named: "chatMessageText") {
                    attrs[.foregroundColor] = color;
                }
                val.append(NSAttributedString(string: " (private message)", attributes: attrs));

                cell.nicknameView?.attributedText = val;
            } else {
                cell.nicknameView?.text = sender;
            }
            cell.set(invitation: item);
            return cell;
        default:
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewMessageCell", for: indexPath);
        }

    }

    override func canExecuteContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ChatEntry, at indexPath: IndexPath) -> Bool {
        switch action {
        case .retract:
            return item.state.direction == .outgoing && XmppService.instance.getClient(for: item.account)?.state ?? .disconnected == .connected && (self.chat as? Room)?.state ?? .not_joined == .joined;
        default:
            return super.canExecuteContext(action: action, forItem: item, at: indexPath);
        }
    }
    
    override func executeContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ChatEntry, at indexPath: IndexPath) {
        switch action {
        case .retract:
            guard let room = self.chat as? Room, item.state.direction == .outgoing else {
                return;
            }
            
            DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
                let message = room.createMessageRetraction(forMessageWithId: originId);
                message.id = UUID().uuidString;
                message.originId = message.id;
                guard let client = XmppService.instance.getClient(for: item.account), client.state == .connected, room.state == .joined else {
                    return;
                }
                client.context.writer?.write(message);
                DBChatHistoryStore.instance.retractMessage(for: item.account, with: item.jid, stanzaId: originId, authorNickname: item.authorNickname, participantId: item.participantId, retractionStanzaId: message.id, retractionTimestamp: Date(), serverMsgId: nil, remoteMsgId: nil);
            })
        default:
            super.executeContext(action: action, forItem: item, at: indexPath);
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOccupants" {
            if let navigation = segue.destination as? UINavigationController {
                if let occupantsController = navigation.visibleViewController as? MucChatOccupantsTableViewController {
                    occupantsController.room = room;
                    occupantsController.account = account;
                    occupantsController.mentionOccupant = { [weak self] name in
                        var text = self?.messageText ?? "";
                        if text.last != " " {
                            text = text + " ";
                        }
                        self?.messageText = "\(text)@\(name) ";
                    }
                }
            } else {
                if let occupantsController = segue.destination as? MucChatOccupantsTableViewController {
                    occupantsController.room = room;
                    occupantsController.account = account;
                    occupantsController.mentionOccupant = { [weak self] name in
                        var text = self?.messageText ?? "";
                        if text.last != " " {
                            text = text + " ";
                        }
                        self?.messageText = "\(text)@\(name) ";
                    }
                }
            }
        }
        super.prepare(for: segue, sender: sender);
    }

    @objc func avatarChanged(_ notification: NSNotification) {
        // TODO: adjust this to make it work properly with MUC
        guard ((notification.userInfo?["jid"] as? BareJID) == jid) else {
            return;
        }
        DispatchQueue.main.async {
            self.conversationLogController?.reloadVisibleItems();
        }
    }

    @objc func accountStateChanged(_ notification: Notification) {
        let account = BareJID(notification.userInfo!["account"]! as! String);
        if self.account == account {
            DispatchQueue.main.async {
                self.updateTitleView();
            }
        }
    }

    fileprivate func updateTitleView() {
        let state = XmppService.instance.getClient(forJid: self.account)?.state;
        DispatchQueue.main.async {
            self.titleView?.connected = state != nil && state == .connected;
        }
    }
    
    @IBAction func sendClicked(_ sender: UIButton) {
        self.sendMessage();
    }

    override func sendMessage() {
        guard let text = messageText, !(text.isEmpty != false), let room = self.room else {
            return;
        }
        
        guard room.state == .joined else {
            let alert = UIAlertController.init(title: "Warning", message: "You are not connected to room.\nPlease wait reconnection to room", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.present(alert, animated: true, completion: nil);
            return;
        }
        
        let canEncrypt = (room.supportedFeatures?.contains("muc_nonanonymous") ?? false) && (room.supportedFeatures?.contains("muc_membersonly") ?? false);
        
        let encryption: ChatEncryption = room.options.encryption ?? (canEncrypt ? (ChatEncryption(rawValue: Settings.messageEncryption.string() ?? "") ?? .none) : .none);
        guard encryption == .none || canEncrypt else {
            if encryption == .omemo && !canEncrypt {
                let alert = UIAlertController(title: "Warning", message: "This room is not capable of sending encrypted messages. Please change encryption settings to be able to send messages", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                self.present(alert, animated: true, completion: nil);
            }
            return;
        }
        
        let msg = self.room!.createMessage(text);
        msg.lastMessageCorrectionId = self.correctedMessageOriginId;

        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }
        
        if encryption == .omemo, let omemoModule: OMEMOModule = client.modulesManager.getModule(OMEMOModule.ID) {
            guard let members = room.members else {
                return;
            }
            omemoModule.encode(message: msg, for: members.map({ $0.bareJid }), completionHandler: { result in
                switch result {
                case .failure(let error):
                    print("could not encrypt message for", room.jid);
                case .successMessage(let message, let fingerprint):
                    client.context.writer?.write(message);
                    DBChatHistoryStore.instance.appendItem(for: self.account, with: self.jid, state: .outgoing, authorNickname: room.nickname, authorJid: nil, recipientNickname: nil, participantId: nil, type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, encryption: .decrypted, encryptionFingerprint: fingerprint, linkPreviewAction: .auto, completionHandler: nil);
                }
            })
        } else {
            client.context.writer?.write(msg);
            DBChatHistoryStore.instance.appendItem(for: self.account, with: self.jid, state: .outgoing, authorNickname: room.nickname, authorJid: nil, recipientNickname: nil, participantId: nil, type: .message, timestamp: Date(), stanzaId: msg.id, serverMsgId: nil, remoteMsgId: nil, data: text, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .auto, completionHandler: nil);
        }
        DispatchQueue.main.async {
            self.messageText = nil;
        }
    }
    
    override func sendAttachment(originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (() -> Void)?) {
        guard let room = self.room else {
            completionHandler?();
            return;
        }
        
        let canEncrypt = (room.supportedFeatures?.contains("muc_nonanonymous") ?? false) && (room.supportedFeatures?.contains("muc_membersonly") ?? false);
        
        let encryption: ChatEncryption = room.options.encryption ?? (canEncrypt ? (ChatEncryption(rawValue: Settings.messageEncryption.string() ?? "") ?? .none) : .none);
        guard encryption == .none || canEncrypt else {
            completionHandler?();
            return;
        }
        
        let msg = room.createMessage(uploadedUrl);
        msg.lastMessageCorrectionId = self.correctedMessageOriginId;

        guard let client = XmppService.instance.getClient(for: account) else {
            completionHandler?();
            return;
        }
        
        if encryption == .omemo, let omemoModule: OMEMOModule = client.modulesManager.getModule(OMEMOModule.ID) {
            guard let members = room.members else {
                completionHandler?();
                return;
            }
            omemoModule.encode(message: msg, for: members.map({ $0.bareJid }), completionHandler: { result in
                switch result {
                case .failure(let error):
                    print("could not encrypt message for", room.jid);
                case .successMessage(let message, let fingerprint):
                    client.context.writer?.write(message);
                    DBChatHistoryStore.instance.appendItem(for: self.account, with: self.jid, state: .outgoing, authorNickname: room.nickname, authorJid: nil, recipientNickname: nil, participantId: nil, type: .attachment, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: uploadedUrl, encryption: .decrypted, encryptionFingerprint: fingerprint, linkPreviewAction: .auto, completionHandler: nil);
                }
                completionHandler?();
            })
        } else {
            msg.oob = uploadedUrl;
            client.context.writer?.write(msg);
            DBChatHistoryStore.instance.appendItem(for: self.account, with: self.jid, state: .outgoing, authorNickname: room.nickname, authorJid: nil, recipientNickname: nil, participantId: nil, type: .attachment, timestamp: Date(), stanzaId: msg.id, serverMsgId: nil, remoteMsgId: nil, data: uploadedUrl, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .auto, completionHandler: nil);
            completionHandler?();
        }
    }
    
    @objc func roomInfoClicked() {
        print("room info for", account as Any, room?.roomJid as Any, "clicked!");
        guard let settingsController = self.storyboard?.instantiateViewController(withIdentifier: "MucChatSettingsViewController") as? MucChatSettingsViewController else {
            return;
        }
        settingsController.account = self.account;
        settingsController.room = self.room;
        
        let navigation = UINavigationController(rootViewController: settingsController);
        navigation.title = self.title;
        navigation.modalPresentationStyle = .formSheet;
        settingsController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: settingsController, action: #selector(MucChatSettingsViewController.dismissView));
        self.present(navigation, animated: true, completion: nil);
        //self.navigationController?.pushViewController(settingsController, animated: true);
    }
    
    @objc func roomStatusChanged(_ notification: Notification) {
        guard let room = notification.object as? DBRoom else {
            return;
        }
        DispatchQueue.main.async {
            guard self.room?.id == room.id else {
                return;
            }
            self.refreshRoomInfo(room);
        }
    }

    func refreshRoomInfo(_ room: DBRoom) {
        titleView?.state = room.state;
        titleView?.name = room.name ?? jid.stringValue;
    }

}

class MucTitleView: UIView {
    
    @IBOutlet var nameView: UILabel!;
    @IBOutlet var statusView: UILabel!;
    var statusViewHeight: NSLayoutConstraint?;
    
    var name: String? {
        get {
            return nameView.text;
        }
        set {
            nameView.text = newValue;
        }
    }
    
    var connected: Bool = false {
        didSet {
            guard connected != oldValue else {
                return;
            }
            
            refresh();
        }
    }
    
    var state: Room.State = Room.State.not_joined {
        didSet {
            refresh();
        }
    }
    
    override func layoutSubviews() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            if UIDevice.current.orientation.isLandscape {
                if statusViewHeight == nil {
                    statusViewHeight = statusView.heightAnchor.constraint(equalToConstant: 0);
                }
                statusViewHeight?.isActive = true;
            } else {
                statusViewHeight?.isActive = false;
                self.refresh();
            }
        }
    }

    func refresh() {
        if connected {
            let statusIcon = NSTextAttachment();
            
            var show: Presence.Show?;
            var desc = "Offline";
            switch state {
            case .joined:
                show = Presence.Show.online;
                desc = "Online";
            case .requested:
                show = Presence.Show.away;
                desc = "Joining...";
            default:
                break;
            }
            
            statusIcon.image = AvatarStatusView.getStatusImage(show);
            let height = statusView.frame.height;
            statusIcon.bounds = CGRect(x: 0, y: -3, width: height, height: height);
            
            let statusText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: statusIcon));
            statusText.append(NSAttributedString(string: desc));
            statusView.attributedText = statusText;
        } else {
            statusView.text = "\u{26A0} Not connected!";
        }
    }
}
