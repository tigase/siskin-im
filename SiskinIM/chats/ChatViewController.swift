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

class ChatViewController : BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar, UITableViewDataSource, BaseChatViewController_ShareImageExtension, BaseChatViewController_PreviewExtension {

    var titleView: ChatTitleView! {
        get {
            return self.navigationItem.titleView as! ChatTitleView;
        }
    }
    
    let log: Logger = Logger();
    
    //var dataSource: ChatViewDataSource = ChatViewDataSource();
    
    var refreshControl: UIRefreshControl!;
    
    @IBOutlet var shareButton: UIButton!;
    @IBOutlet var progressBar: UIProgressView!;
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?;
    var filePickerDelegate: BaseChatViewController_ShareFilePickerDelegate?;
    
    fileprivate static let loadChatInfo: DBStatement = try! DBConnection.main.prepareStatement("SELECT r.name FROM roster_items r WHERE r.account = :account AND r.jid = :jid");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let messageModule: MessageModule? = xmppService.getClient(forJid: account)?.modulesManager.getModule(MessageModule.ID);
        self.chat = messageModule?.chatManager.getChat(with: JID(self.jid), thread: nil) as? DBChat;
        
        tableView.dataSource = self;
        tableView.delegate = self;
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        
//        let navBarHeight = self.navigationController!.navigationBar.frame.size.height;
//        let width = CGFloat(220);

//        titleView = ChatTitleView(width: width, height: navBarHeight);
//        titleView.name = navigationItem.title;
        
//        let buddyBtn = UIButton(type: .system);
//        buddyBtn.frame = CGRect(x: 0, y: 0, width: width, height: navBarHeight);
//        buddyBtn.addSubview(titleView);
        
//        buddyBtn.addTarget(self, action: #selector(ChatViewController.showBuddyInfo), for: .touchDown);
        //self.navigationItem.titleView = buddyBtn;
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(ChatViewController.showBuddyInfo));
        self.titleView.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);

        self.refreshControl = UIRefreshControl();
        self.refreshControl?.addTarget(self, action: #selector(ChatViewController.refreshChatHistory), for: UIControl.Event.valueChanged);
        self.tableView.addSubview(refreshControl);
        initSharing();
        
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(chatChanged(_:)), name: DBChatStore.CHAT_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged(_:)), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated(_:)), name: DBRosterStore.ITEM_UPDATED, object: self);

    }
    
    @objc func showBuddyInfo() {//_ button: UIButton) {
        print("open buddy info!");
        let navigation = storyboard?.instantiateViewController(withIdentifier: "ContactViewNavigationController") as! UINavigationController;
        let contactView = navigation.visibleViewController as! ContactViewController;
        contactView.account = account;
        contactView.jid = jid;
        contactView.chat = self.chat as! DBChat;
        contactView.showEncryption = true;
        navigation.title = self.navigationItem.title;
        navigation.modalPresentationStyle = .formSheet;
        self.present(navigation, animated: true, completion: nil);

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        self.updateTitleView();
        
        let presenceModule: PresenceModule? = xmppService.getClient(forJid: account)?.modulesManager.getModule(PresenceModule.ID);
        titleView.status = presenceModule?.presenceStore.getBestPresence(for: jid);
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self);
        super.viewDidDisappear(animated);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if dataSource.count == 0 {
            let label = UILabel(frame: CGRect(x: 0, y:0, width: self.view.bounds.size.width, height: self.view.bounds.size.height));
            label.text = "No messages available. Pull up to refresh message history.";
            label.numberOfLines = 0;
            label.textAlignment = .center;
            label.transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0);
            label.sizeToFit();
            label.textColor = Appearance.current.labelColor;
            self.tableView.backgroundView = label;
        } else {
            self.tableView.backgroundView = nil;
        }
        return dataSource.count;
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let dsItem = dataSource.getItem(at: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewCellIncoming", for: indexPath);
        }

        switch dsItem {
        case let item as ChatMessage:
            var continuation = false;
            if Settings.EnableNewUI.getBool() && (indexPath.row + 1) < dataSource.count {
                if let prevItem = dataSource.getItem(at: indexPath.row + 1) {
                    continuation = item.isMergeable(with: prevItem);
                }
            }
            let incoming = item.state.direction == .incoming;
            let id = Settings.EnableNewUI.getBool() ? (continuation ? "ChatTableViewCellContinuation" : "ChatTableViewCell") : (incoming ? "ChatTableViewCellIncoming" : "ChatTableViewCellOutgoing");
            let cell: ChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            let name = incoming ? self.titleView.name : "Me";
            cell.avatarView?.set(name: name, avatar: AvatarManager.instance.avatar(for: incoming ? jid : account, on: account), orDefault: AvatarManager.instance.defaultAvatar);
            cell.nicknameView?.text = name;
            cell.set(message: item, downloader: self.downloadPreview(url:msgId:account:jid:));
            cell.setNeedsUpdateConstraints();
            cell.updateConstraintsIfNeeded();
            
            return cell;
        case let item as SystemMessage:
            let cell: ChatTableViewSystemCell = tableView.dequeueReusableCell(withIdentifier: "ChatTableViewSystemCell", for: indexPath) as! ChatTableViewSystemCell;
            cell.set(item: item);
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            return cell;
        default:
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewCellIncoming", for: indexPath);
        }
    }
    
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        print("accessory button cliecked at", indexPath)
        guard let item = dataSource.getItem(at: indexPath.row) as? ChatMessage else {
            return;
        }
        
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Details", message: item.error ?? "Unknown error occurred", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Resend", style: .default, handler: {(action) in
                print("resending message with body", item.message);
                let url = item.message.starts(with: "http:") || item.message.starts(with: "https:") ? item.message : nil;
                self.sendMessage(body: item.message, url: url, completed: nil);
                DBChatHistoryStore.instance.removeItem(for: item.account, with: item.jid, itemId: item.id);
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    @IBAction func shareClicked(_ sender: UIButton) {
        self.showPhotoSelector(sender);
    }
            
    @objc func avatarChanged(_ notification: NSNotification) {
        guard ((notification.userInfo?["jid"] as? BareJID) == jid) else {
            return;
        }
        DispatchQueue.main.async {
            if let indexPaths = self.tableView.indexPathsForVisibleRows {
                self.tableView.reloadRows(at: indexPaths, with: .none);
            }
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
        let state = xmppService.getClient(forJid: self.account)?.state;

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
        VideoCallController.call(jid: self.jid, from: self.account, withAudio: true, withVideo: false, sender: self);
    }
    
    @objc func videoCall() {
        VideoCallController.call(jid: self.jid, from: self.account, withAudio: true, withVideo: true, sender: self);
    }
    #endif
    
    @objc func refreshChatHistory() {
        let syncPeriod = AccountSettings.messageSyncPeriod(account).getDouble();
        guard syncPeriod != 0 else {
            self.refreshControl.endRefreshing();
            return;
        }

        let date = Date().addingTimeInterval(syncPeriod * -60.0 * 60);
        syncHistory(start: date);
    }
    
    func syncHistory(start: Date, rsm rsmQuery: RSM.Query? = nil) {
        guard let mamModule: MessageArchiveManagementModule = self.xmppService.getClient(forJid: self.account)?.modulesManager.getModule(MessageArchiveManagementModule.ID) else {
            self.refreshControl.endRefreshing();
            return;
        }
        
        mamModule.queryItems(with: JID(jid), start: start, queryId: "sync-2", rsm: rsmQuery ?? RSM.Query(lastItems: 100), onSuccess: {(queryid,complete,rsmResponse) in
            self.log("received items from archive", queryid, complete, rsmResponse);
            if rsmResponse != nil && rsmResponse!.index != 0 && rsmResponse?.first != nil {
                self.syncHistory(start: start, rsm: rsmResponse?.previous(100));
            } else {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
                    self.refreshControl.endRefreshing();
                }
            }
        }, onError: {(error,stanza) in
            self.log("failed to retrieve items from archive", error, stanza);
            DispatchQueue.main.async {
                self.refreshControl.endRefreshing();
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
        
        sendMessage(body: text!, completed: {() in
            DispatchQueue.main.async {
                self.messageText = nil;
            }
        });
    }
    
    func sendMessage(body: String, url: String? = nil, preview: String? = nil, completed: (()->Void)?) {
        MessageEventHandler.sendMessage(chat: self.chat as! DBChat, body: body, url: url);
        completed?();
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
        let params:[String:Any?] = ["account" : account, "jid" : jid];
        let name = try! ChatViewController.loadChatInfo.findFirst(params) { (cursor) -> (String)? in
            return cursor["name"] ?? jid.stringValue;
            } ?? jid.stringValue;
        
        self.name = name;
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
            self.nameView.textColor = Appearance.current.navigationBarTextColor;
            self.statusView.textColor = Appearance.current.navigationBarTextColor;
            
        }
    }
}
