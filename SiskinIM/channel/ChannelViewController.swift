//
// ChannelViewController.swift
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

class ChannelViewController: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar, BaseChatViewController_ShareImageExtension {

    var progressBar: UIProgressView?
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?
    var filePickerDelegate: BaseChatViewController_ShareFilePickerDelegate?
    
    var titleView: ChannelTitleView? {
        get {
            return self.navigationItem.titleView as? ChannelTitleView
        }
    }
    
    var channel: DBChannel? {
        get {
            return self.chat as? DBChannel;
        }
        set {
            self.chat = newValue;
        }
    }
    
    override func viewDidLoad() {
        chat = DBChatStore.instance.getChat(for: account, with: jid);
        super.viewDidLoad();
        
        navigationItem.title = channel?.name ?? jid.stringValue;
        titleView?.channel = channel;
        navigationItem.rightBarButtonItem?.isEnabled = (channel?.state ?? .left) == .joined;
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(channelInfoClicked));
        self.titleView?.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);

        initializeSharing();
        NotificationCenter.default.addObserver(self, selector: #selector(channelUpdated(_:)), name: DBChatStore.CHAT_UPDATED, object: channel);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged(_:)), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged(_:)), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        navigationItem.rightBarButtonItem?.isEnabled = (channel?.state ?? .left) == .joined;
        titleView?.connected = XmppService.instance.getClient(for: account)?.state ?? .disconnected == .connected;
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
            let id = continuation ? "ChatTableViewMessageContinuationCell" : "ChatTableViewMessageCell";

            let cell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
            cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            //        cell.nicknameLabel?.text = item.nickname;
            if cell.avatarView != nil {
                if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                    cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                } else if let participantId = item.participantId {
                    cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(item.jid.localPart!)", domain: item.jid.domain), on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                } else {
                    cell.avatarView?.set(name: item.authorNickname, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                }
            }
            cell.nicknameView?.text = item.authorNickname;

            cell.set(message: item);
            return cell;
        case let item as ChatAttachment:
            let id = continuation ? "ChatTableViewAttachmentContinuationCell" : "ChatTableViewAttachmentCell";
            let cell: AttachmentChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! AttachmentChatTableViewCell;
            cell.contentView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            if cell.avatarView != nil {
                if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                    cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                } else if let participantId = item.participantId {
                    cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(item.jid.localPart!)", domain: item.jid.domain), on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                } else {
                    cell.avatarView?.set(name: item.authorNickname, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                }
            }
            cell.nicknameView?.text = item.authorNickname;

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
                if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                    cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                } else if let participantId = item.participantId {
                    cell.avatarView?.set(name: item.authorNickname, avatar: AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(item.jid.localPart!)", domain: item.jid.domain), on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                } else {
                    cell.avatarView?.set(name: item.authorNickname, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                }
            }
            cell.nicknameView?.text = item.authorNickname;
            cell.set(invitation: item);
            return cell;
        default:
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewMessageCell", for: indexPath);
        }

    }

    override func canExecuteContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ChatEntry, at indexPath: IndexPath) -> Bool {
        switch action {
        case .retract:
            return item.state.direction == .outgoing && XmppService.instance.getClient(for: item.account)?.state ?? .disconnected == .connected && (self.chat as? Channel)?.state ?? .left == .joined;
        default:
            return super.canExecuteContext(action: action, forItem: item, at: indexPath);
        }
    }
    
    override func executeContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ChatEntry, at indexPath: IndexPath) {
        switch action {
        case .retract:
            guard let channel = self.chat as? Channel, item.state.direction == .outgoing else {
                return;
            }
            
            DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
                let message = channel.createMessageRetraction(forMessageWithId: originId);
                message.id = UUID().uuidString;
                message.originId = message.id;
                guard let client = XmppService.instance.getClient(for: item.account), client.state == .connected, channel.state == .joined else {
                    return;
                }
                client.context.writer?.write(message);
                DBChatHistoryStore.instance.retractMessage(for: item.account, with: item.jid, stanzaId: originId, authorNickname: item.authorNickname, participantId: item.participantId, retractionStanzaId: message.id, retractionTimestamp: Date(), serverMsgId: nil, remoteMsgId: nil);
            })
        default:
            super.executeContext(action: action, forItem: item, at: indexPath);
        }
    }
    
    @objc func accountStateChanged(_ notification: Notification) {
        let account = BareJID(notification.userInfo!["account"]! as! String);
        if self.account == account {
            DispatchQueue.main.async {
                self.titleView?.connected = XmppService.instance.getClient(for: account)?.state ?? .disconnected == .connected;
            }
        }
    }

    @objc func avatarChanged(_ notification: Notification) {
        guard ((notification.userInfo?["jid"] as? BareJID) == jid) else {
            return;
        }
        DispatchQueue.main.async {
            self.conversationLogController?.reloadVisibleItems();
        }
    }
    
    @objc func channelUpdated(_ notification: Notification) {
        DispatchQueue.main.async {
            self.titleView?.refresh();
            self.navigationItem.rightBarButtonItem?.isEnabled = (self.channel?.state ?? .left) == .joined;
        }
    }

    @IBAction func sendClicked(_ sender: UIButton) {
        self.sendMessage();
    }

    @objc func channelInfoClicked() {
        self.performSegue(withIdentifier: "ChannelSettingsShow", sender: self);
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender);
        if let destination = (segue.destination as? UINavigationController)?.topViewController as? ChannelSettingsViewController {
            destination.channel = self.channel;
        }
        if let destination = segue.destination as? ChannelParticipantsController {
            destination.channel = self.channel;
        }
    }
    
    override func sendMessage() {
        let text = messageText;
        guard !(text?.isEmpty != false) else {
            return;
        }
        
        guard channel?.state == .joined else {
            let alert: UIAlertController?  = UIAlertController.init(title: "Warning", message: "You are not joined to the channel.", preferredStyle: .alert);
            alert?.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.present(alert!, animated: true, completion: nil);
            return;
        }
        
        let msg = self.channel!.createMessage(text);
        msg.lastMessageCorrectionId = self.correctedMessageOriginId;
        XmppService.instance.getClient(for: account)?.context.writer?.write(msg);
        DispatchQueue.main.async {
            self.messageText = nil;
        }
    }
    
    func sendAttachment(originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (() -> Void)?) {
        let msg = self.channel!.createMessage(uploadedUrl);
        msg.oob = uploadedUrl;
        XmppService.instance.getClient(for: account)?.context.writer?.write(msg);
        completionHandler?();
    }
    
}

class ChannelTitleView: UIView {
    
    @IBOutlet var nameView: UILabel!;
    @IBOutlet var statusView: UILabel!;
    
    var statusViewHeight: NSLayoutConstraint?;

    var connected: Bool = false {
        didSet {
            guard connected != oldValue else {
                return;
            }
            refresh();
        }
    }
    
    var channel: DBChannel? {
        didSet {
            nameView.text = channel?.name ?? channel?.jid.stringValue ?? "";
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
            switch channel?.state ?? .left {
            case .joined:
                show = Presence.Show.online;
                desc = "Joined";
            case .left:
                show = nil;
                desc = "Not joined";
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
