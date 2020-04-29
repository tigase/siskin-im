//
// ChatViewController.swift
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
import Shared
import TigaseSwift
import TigaseSwiftOMEMO

class ChatViewController : BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar, BaseChatViewController_ShareImageExtension {

    var titleView: ChatTitleView! {
        get {
            return (self.navigationItem.titleView as! ChatTitleView);
        }
    }
    
    let log: Logger = Logger();
            
    var progressBar: UIProgressView?;
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?;
    var filePickerDelegate: BaseChatViewController_ShareFilePickerDelegate?;
    
    override var conversationLogController: ConversationLogController? {
        didSet {
            if conversationLogController != nil {
                let refreshControl = UIRefreshControl();
                refreshControl.addTarget(self, action: #selector(ChatViewController.refreshChatHistory), for: UIControl.Event.valueChanged);
                self.conversationLogController?.refreshControl = refreshControl;
            }
        }
    }
    
    override func conversationTableViewDelegate() -> UITableViewDelegate? {
        return self;
    }
        
    override func viewDidLoad() {
        let messageModule: MessageModule? = XmppService.instance.getClient(forJid: account)?.modulesManager.getModule(MessageModule.ID);
        self.chat = messageModule?.chatManager.getChat(with: JID(self.jid), thread: nil) as? DBChat;
        
        super.viewDidLoad()
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(ChatViewController.showBuddyInfo));
        self.titleView.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);

        initializeSharing();
        
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(chatChanged(_:)), name: DBChatStore.CHAT_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged(_:)), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated(_:)), name: DBRosterStore.ITEM_UPDATED, object: self);

    }
    
    @objc func showBuddyInfo(_ button: Any) {
        print("open buddy info!");
        let navigation = storyboard?.instantiateViewController(withIdentifier: "ContactViewNavigationController") as! UINavigationController;
        let contactView = navigation.visibleViewController as! ContactViewController;
        contactView.account = account;
        contactView.jid = jid;
        contactView.chat = self.chat as? DBChat;
        //contactView.showEncryption = true;
        navigation.title = self.navigationItem.title;
        navigation.modalPresentationStyle = .formSheet;
        self.present(navigation, animated: true, completion: nil);

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        self.updateTitleView();
        
        let presenceModule: PresenceModule? = XmppService.instance.getClient(forJid: account)?.modulesManager.getModule(PresenceModule.ID);
        titleView.status = presenceModule?.presenceStore.getBestPresence(for: jid);
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        //NotificationCenter.default.removeObserver(self);
        super.viewDidDisappear(animated);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
        
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = super.tableView(tableView, numberOfRowsInSection: section);
        if count == 0 {
            if self.conversationLogController!.tableView.backgroundView == nil {
                let label = UILabel(frame: CGRect(x: 0, y:0, width: self.view.bounds.size.width, height: self.view.bounds.size.height));
                label.text = "No messages available. Pull up to refresh message history.";
                label.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium);
                label.numberOfLines = 0;
                label.textAlignment = .center;
                label.transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0);
                label.sizeToFit();
                self.conversationLogController!.tableView.backgroundView = label;
            }
        } else {
            self.conversationLogController!.tableView.backgroundView = nil;
        }
        return count;
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let dsItem = dataSource.getItem(at: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewCellIncoming", for: indexPath);
        }

        var continuation = false;
        if (indexPath.row + 1) < dataSource.count {
            if let prevItem = dataSource.getItem(at: indexPath.row + 1) {
                continuation = dsItem.isMergeable(with: prevItem);
            }
        }
        let incoming = dsItem.state.direction == .incoming;
        
        switch dsItem {
        case let item as ChatMessage:
            let id = continuation ? "ChatTableViewMessageContinuationCell" : "ChatTableViewMessageCell";
            let cell: ChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            let name = incoming ? self.titleView.name : "Me";
            cell.avatarView?.set(name: name, avatar: AvatarManager.instance.avatar(for: incoming ? jid : account, on: account), orDefault: AvatarManager.instance.defaultAvatar);
            cell.nicknameView?.text = name;
            cell.set(message: item);
//            cell.setNeedsUpdateConstraints();
//            cell.updateConstraintsIfNeeded();
            
            return cell;
        case let item as ChatAttachment:
            let id = continuation ? "ChatTableViewAttachmentContinuationCell" : "ChatTableViewAttachmentCell" ;
            let cell: AttachmentChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! AttachmentChatTableViewCell;
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            let name = incoming ? self.titleView.name : "Me";
            cell.avatarView?.set(name: name, avatar: AvatarManager.instance.avatar(for: incoming ? jid : account, on: account), orDefault: AvatarManager.instance.defaultAvatar);
            cell.nicknameView?.text = name;
            cell.set(attachment: item);
//            cell.setNeedsUpdateConstraints();
//            cell.updateConstraintsIfNeeded();
            
            return cell;
        case let item as ChatLinkPreview:
            let id = "ChatTableViewLinkPreviewCell";
            let cell: LinkPreviewChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! LinkPreviewChatTableViewCell;
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            cell.set(linkPreview: item);
            return cell;
        case let item as SystemMessage:
            let cell: ChatTableViewSystemCell = tableView.dequeueReusableCell(withIdentifier: "ChatTableViewSystemCell", for: indexPath) as! ChatTableViewSystemCell;
            cell.set(item: item);
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            return cell;
        case let item as ChatInvitation:
            let id = "ChatTableViewInvitationCell";
            let cell: InvitationChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! InvitationChatTableViewCell;
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            let name = incoming ? self.titleView.name : "Me";
            cell.avatarView?.set(name: name, avatar: AvatarManager.instance.avatar(for: incoming ? jid : account, on: account), orDefault: AvatarManager.instance.defaultAvatar);
            cell.nicknameView?.text = name;
            cell.set(invitation: item);
            return cell;
        default:
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewCellIncoming", for: indexPath);
        }
    }
    
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        print("accessory button cliecked at", indexPath)
        guard let item = dataSource.getItem(at: indexPath.row) as? ChatEntry, let chat = self.chat as? DBChat else {
            return;
        }
        
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Details", message: item.error ?? "Unknown error occurred", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Resend", style: .default, handler: {(action) in
                //print("resending message with body", item.message);
                
                switch item {
                case let item as ChatMessage:
                    MessageEventHandler.sendMessage(chat: chat, body: item.message, url: nil);
                    DBChatHistoryStore.instance.remove(item: item);
                case let item as ChatAttachment:
                    let oldLocalFile = DownloadStore.instance.url(for: "\(item.id)");
                    MessageEventHandler.sendAttachment(chat: chat, originalUrl: oldLocalFile, uploadedUrl: item.url, appendix: item.appendix, completionHandler: {
                        DBChatHistoryStore.instance.remove(item: item);
                    });
                default:
                    break;
                }
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            self.present(alert, animated: true, completion: nil);
        }
    }
                
    @objc func avatarChanged(_ notification: NSNotification) {
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
    
    @objc func chatChanged(_ notification: Notification) {
        guard let chat = notification.object as? DBChat else {
            return;
        }
        guard self.account == chat.account && self.jid == chat.jid.bareJid else {
            return;
        }
        
        DispatchQueue.main.async {
            self.chat = chat;
            
            self.titleView.encryption = chat.options.encryption;//(notification.userInfo?["encryption"] as? ChatEncryption) ?? .none;
        }
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let cpc = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard cpc.presence.from?.bareJid == self.jid && cpc.sessionObject.userBareJid == account else {
            return;
        }

        DispatchQueue.main.async() {
            self.titleView.status = cpc.presence;
            self.updateTitleView();
        }
    }
    
    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        guard e.sessionObject.userBareJid != nil && e.rosterItem != nil else {
            return;
        }
        guard e.sessionObject.userBareJid! == self.account && e.rosterItem!.jid.bareJid == self.jid else {
            return;
        }
        DispatchQueue.main.async {
            self.titleView.name = e.rosterItem!.name ?? e.rosterItem!.jid.stringValue;
        }
    }
    
    fileprivate func updateTitleView() {
        let state = XmppService.instance.getClient(forJid: self.account)?.state;

        titleView.reload(for: self.account, with: self.jid);

        DispatchQueue.main.async {
            self.titleView.connected = state != nil && state == .connected;
        }
        #if targetEnvironment(simulator)
        #else
        let jingleSupported = JingleManager.instance.support(for: JID(self.jid), on: self.account);
        var count = jingleSupported.contains(.audio) ? 1 : 0;
        if jingleSupported.contains(.video) {
            count = count + 1;
        }
        DispatchQueue.main.async {
            guard (self.navigationItem.rightBarButtonItems?.count ?? 0 != count) else {
                return;
            }
            var buttons: [UIBarButtonItem] = [];
            if jingleSupported.contains(.video) {
                //buttons.append(UIBarButtonItem(image: UIImage(named: "videoCall"), style: .plain, target: self, action: #selector(self.videoCall)));
                buttons.append(self.smallBarButtinItem(image: UIImage(named: "videoCall")!, action: #selector(self.videoCall)));
            }
            if jingleSupported.contains(.audio) {
                //buttons.append(UIBarButtonItem(image: UIImage(named: "audioCall"), style: .plain, target: self, action: #selector(self.audioCall)));
                buttons.append(self.smallBarButtinItem(image: UIImage(named: "audioCall")!, action: #selector(self.audioCall)));
            }
            self.navigationItem.rightBarButtonItems = buttons;
        }
        #endif
    }
    
    fileprivate func smallBarButtinItem(image: UIImage, action: Selector) -> UIBarButtonItem {
        let btn = UIButton(type: .custom);
        btn.setImage(image, for: .normal);
        btn.addTarget(self, action: action, for: .touchUpInside);
        btn.frame = CGRect(x: 0, y: 0, width: 30, height: 30);
        return UIBarButtonItem(customView: btn);
    }
    
    #if targetEnvironment(simulator)
    #else
    @objc func audioCall() {
        VideoCallController.call(jid: self.jid, from: self.account, media: [.audio], sender: self);
    }
    
    @objc func videoCall() {
        VideoCallController.call(jid: self.jid, from: self.account, media: [.audio, .video], sender: self);
    }
    #endif
    
    @objc func refreshChatHistory() {
        let syncPeriod = AccountSettings.messageSyncPeriod(account).getDouble();
        guard syncPeriod != 0 else {
            self.conversationLogController?.refreshControl?.endRefreshing();
            return;
        }

        let date = Date().addingTimeInterval(syncPeriod * -60.0 * 60);
        syncHistory(start: date);
    }
    
    func syncHistory(start: Date, rsm rsmQuery: RSM.Query? = nil) {
        guard let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(forJid: self.account)?.modulesManager.getModule(MessageArchiveManagementModule.ID) else {
            self.conversationLogController?.refreshControl?.endRefreshing();
            return;
        }
        
        mamModule.queryItems(with: JID(jid), start: start, queryId: "sync-2", rsm: rsmQuery ?? RSM.Query(lastItems: 100), completionHandler: { result in
            switch result {
            case .success(let queryId, let complete, let rsmResponse):
                self.log("received items from archive", queryId, complete, rsmResponse);
                if rsmResponse != nil && rsmResponse!.index != 0 && rsmResponse?.first != nil {
                    self.syncHistory(start: start, rsm: rsmResponse?.previous(100));
                } else {
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
                        self.conversationLogController?.refreshControl?.endRefreshing();
                    }
                }
            case .failure(let errorCondition, let response):
                self.log("failed to retrieve items from archive", errorCondition, response);
                DispatchQueue.main.async {
                    self.conversationLogController?.refreshControl?.endRefreshing();
                }
            }
        });
    }
    
    @IBAction func sendClicked(_ sender: UIButton) {
        sendMessage();
    }
    
    override func sendMessage() {
        let text = messageText;
        guard !(text?.isEmpty != false) else {
            return;
        }
        
        MessageEventHandler.sendMessage(chat: self.chat as! DBChat, body: text, url: nil);
        DispatchQueue.main.async {
            self.messageText = nil;
        }
    }
    
    
    func sendAttachment(originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (() -> Void)?) {
        guard let chat = self.chat as? DBChat else {
            completionHandler?();
            return;
        }
        MessageEventHandler.sendAttachment(chat: chat, originalUrl: originalUrl, uploadedUrl: uploadedUrl, appendix: appendix, completionHandler: completionHandler);
    }
        
}

class ChatTitleView: UIView {
    
    @IBOutlet var nameView: UILabel!;
    @IBOutlet var statusView: UILabel!;
    var statusViewHeight: NSLayoutConstraint?;

    var encryption: ChatEncryption? = nil {
        didSet {
            self.refresh();
        }
    }
    
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
            guard oldValue != connected else {
                return;
            }
            refresh();
        }
    }
    
    var status: Presence? {
        didSet {
            self.refresh();
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
    
    
    func reload(for account: BareJID, with jid: BareJID) {
        if let rosterModule: RosterModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(RosterModule.ID) {
            self.name = rosterModule.rosterStore.get(for: JID(jid))?.name ?? jid.stringValue;
        } else {
            self.name = jid.stringValue;
        }
        self.encryption = (DBChatStore.instance.getChat(for: account, with: jid) as? DBChat)?.options.encryption;
    }
    
    fileprivate func refresh() {
        DispatchQueue.main.async {
            let encryption = self.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.getString() ?? "") ?? .none;
            if self.connected {
                let statusIcon = NSTextAttachment();
                statusIcon.image = AvatarStatusView.getStatusImage(self.status?.show);
                let height = self.statusView.frame.height;
                statusIcon.bounds = CGRect(x: 0, y: -3, width: height, height: height);
                var desc = self.status?.status;
                if desc == nil {
                    let show = self.status?.show;
                    if show == nil {
                        desc = "Offline";
                    } else {
                        switch(show!) {
                        case .online:
                            desc = "Online";
                        case .chat:
                            desc = "Free for chat";
                        case .away:
                            desc = "Be right back";
                        case .xa:
                            desc = "Away";
                        case .dnd:
                            desc = "Do not disturb";
                        }
                    }
                }
                let statusText = NSMutableAttributedString(string: encryption == .none ? "" : "\u{1F512} ");
                statusText.append(NSAttributedString(attachment: statusIcon));
                statusText.append(NSAttributedString(string: desc!));
                self.statusView.attributedText = statusText;
            } else {
                switch encryption {
                case .omemo:
                    self.statusView.text = "\u{1F512} \u{26A0} Not connected!";
                case .none:
                    self.statusView.text = "\u{26A0} Not connected!";
                }
            }            
        }
    }
}
