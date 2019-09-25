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
import TigaseSwift
import TigaseSwiftOMEMO

class ChatViewController : BaseChatViewControllerWithContextMenuAndToolbar, BaseChatViewControllerWithContextMenuAndToolbarDelegate, UITableViewDataSource, EventHandler, CachedViewControllerProtocol, BaseChatViewController_ShareImageExtension, BaseChatViewController_PreviewExtension {

    var titleView: ChatTitleView! {
        get {
            return self.navigationItem.titleView as! ChatTitleView;
        }
    }
    
    let log: Logger = Logger();
    var chat: DBChat?;
    
    var dataSource: ChatDataSource!;
    var cachedDataSource: CachedViewDataSourceProtocol {
        return dataSource as CachedViewDataSourceProtocol;
    }
    
    var refreshControl: UIRefreshControl!;
    
    @IBOutlet var shareButton: UIButton!;
    @IBOutlet var progressBar: UIProgressView!;
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?;
    var filePickerDelegate: BaseChatViewController_ShareFilePickerDelegate?;
    
    fileprivate static let loadChatInfo: DBStatement = try! DBConnection.main.prepareStatement("SELECT r.name FROM roster_items r WHERE r.account = :account AND r.jid = :jid");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let messageModule: MessageModule? = xmppService.getClient(forJid: account)?.modulesManager.getModule(MessageModule.ID);
        self.chat = messageModule?.chatManager.getChat(with: self.jid, thread: nil) as? DBChat;
        
        dataSource = ChatDataSource(controller: self);
        contextMenuDelegate = self;
        scrollDelegate = self;
        self.initialize();
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
    }
    
    func getTextOfSelectedRows(paths: [IndexPath], withTimestamps: Bool, handler: (([String]) -> Void)?) {
        let items: [ChatViewItem] = paths.map({ index in dataSource.getItem(for: index) }).filter({ it -> Bool in
            return it != nil;
        }).map({ it -> ChatViewItem in return it! })
            .sorted { (it1, it2) -> Bool in
                it1.timestamp.compare(it2.timestamp) == .orderedAscending;
            };
        
        guard items.count > 1 else {
            let texts = items.map({ (it) -> String in
                return it.data ?? "";
            });
            handler?(texts);
            return;
        }
        
        let withoutPrefix = Set(items.map({it in it.state.direction})).count == 1;
        
        let formatter = DateFormatter();
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy jj:mm", options: 0, locale: NSLocale.current);
        
        var direction: DBChatHistoryStore.MessageDirection? = nil;
        let texts = items.map { (it) -> String in
            if withoutPrefix {
                if withTimestamps {
                    return "[\(formatter.string(from: it.timestamp))] \(it.data ?? "")";
                } else {
                    return it.data ?? "";
                }
            } else {
                let prefix = (direction == nil || it.state.direction != direction!) ?
                    "\(it.state.direction == .incoming ? self.navigationItem.title! : "Me"):\n" : "";
                direction = it.state.direction;
                if withTimestamps {
                    return "\(prefix)  [\(formatter.string(from: it.timestamp))] \(it.data ?? "")"
                } else {
                    return "\(prefix)  \(it.data ?? "")"
                }
            }
        }
        
        print("got texts", texts);
        handler?(texts);
    }
    
    @objc func showBuddyInfo() {//_ button: UIButton) {
        print("open buddy info!");
        let navigation = storyboard?.instantiateViewController(withIdentifier: "ContactViewNavigationController") as! UINavigationController;
        let contactView = navigation.visibleViewController as! ContactViewController;
        contactView.account = account;
        contactView.jid = jid.bareJid;
        contactView.chat = self.chat;
        contactView.showEncryption = true;
        navigation.title = self.navigationItem.title;
        navigation.modalPresentationStyle = .formSheet;
        self.present(navigation, animated: true, completion: nil);

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(chatChanged(_:)), name: DBChatStore.CHAT_UPDATED, object: nil);
        xmppService.registerEventHandler(self, for: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
        
        self.updateTitleView();

        let presenceModule: PresenceModule? = xmppService.getClient(forJid: account)?.modulesManager.getModule(PresenceModule.ID);
        titleView.status = presenceModule?.presenceStore.getBestPresence(for: jid.bareJid);
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self);
        super.viewDidDisappear(animated);
        
        xmppService.unregisterEventHandler(self, for: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
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
        if dataSource.numberOfMessages == 0 {
            let label = UILabel(frame: CGRect(x: 0, y:0, width: self.view.bounds.size.width, height: self.view.bounds.size.height));
            label.text = "No messages available. Pull up to refresh message history.";
            label.numberOfLines = 0;
            label.textAlignment = .center;
            label.transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0);
            label.sizeToFit();
            label.textColor = Appearance.current.labelColor;
            self.tableView.backgroundView = label;
        }
        return dataSource.numberOfMessages;
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = dataSource.getItem(for: indexPath) else {
            return tableView.dequeueReusableCell(withIdentifier: "ChatTableViewCellIncoming", for: indexPath);
        }
        var continuation = false;
        if Settings.EnableNewUI.getBool() && (indexPath.row + 1) < dataSource.numberOfMessages {
            if let prevItem = dataSource.getItem(for: IndexPath(row: indexPath.row + 1, section: 0)) {
                continuation = prevItem.state.direction == item.state.direction && (abs(item.timestamp.timeIntervalSince(prevItem.timestamp)) < 30.0);
            }
        }
        let incoming = item.state.direction == .incoming;
        let id = Settings.EnableNewUI.getBool() ? (continuation ? "ChatTableViewCellContinuation" : "ChatTableViewCell") : (incoming ? "ChatTableViewCellIncoming" : "ChatTableViewCellOutgoing");
        let cell: ChatTableViewCell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
        cell.transform = cachedDataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
        cell.avatarView?.updateAvatar(manager: self.xmppService.avatarManager, for: account, with: incoming ? jid.bareJid : account, name: self.titleView.name, orDefault: self.xmppService.avatarManager.defaultAvatar);
        cell.setValues(data: item.data, ts: item.timestamp, id: item.id, nickname: incoming ? (self.titleView.name ?? self.jid!.bareJid.stringValue) : "Me", state: item.state, messageEncryption: item.encryption, preview: item.preview, downloader: self.downloadPreview);
        cell.setNeedsUpdateConstraints();
        cell.updateConstraintsIfNeeded();
        
        return cell;
    }
    
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        print("accessory button cliecked at", indexPath)
        guard let item = dataSource.getItem(for: indexPath) else {
            return;
        }
        print("cliked message with id", item.id);
        guard item.data != nil else {
            return;
        }
        
        self.xmppService.dbChatHistoryStore.getMessageError(msgId: item.id) { error in
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Details", message: error ?? "Unknown error occurred", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "Resend", style: .default, handler: {(action) in
                    print("resending message with body", item.data ?? "<nil>");
                    self.sendMessage(body: item.data!, completed: nil);
                }));
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
                self.present(alert, animated: true, completion: nil);
            }
        }
    }
    
    @IBAction func shareClicked(_ sender: UIButton) {
        self.showPhotoSelector(sender);
    }
    
    func updateItem(msgId: Int, handler: @escaping (BaseChatViewController_PreviewExtension_PreviewAwareItem) -> Void) {
        DispatchQueue.main.async {
            if let indexPath = self.dataSource.getIndexPath(withId: msgId) {
                if let item = self.dataSource.getItem(for: indexPath) {
                    handler(item);
                    self.tableView.reloadRows(at: [indexPath], with: .automatic);
                }
            }
        }
    }
    
    class ChatViewItem: CachedViewDataSourceItem, BaseChatViewController_PreviewExtension_PreviewAwareItem {
        let id: Int;
        var state: DBChatHistoryStore.State;
        let data: String?;
        let timestamp: Date;
        let encryption: MessageEncryption;
        let fingerprint: String?;
        var preview: String?;
        
        init(cursor: DBCursor) {
            id = cursor["id"]!;
            state = DBChatHistoryStore.State(rawValue: cursor["state"]!)!;
            data = cursor["data"];
            timestamp = cursor["timestamp"]!;
            preview = cursor["preview"];
            encryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
            fingerprint = cursor["fingerprint"];
        }
        
    }
    
    func handle(event: Event) {
        switch event {
        case let cpc as PresenceModule.ContactPresenceChanged:
            guard cpc.presence.from?.bareJid == self.jid.bareJid && cpc.sessionObject.userBareJid == account else {
                return;
            }
            
            DispatchQueue.main.async() {
                self.titleView.status = cpc.presence;
                self.updateTitleView();
            }
        case let e as RosterModule.ItemUpdatedEvent:
            guard e.sessionObject.userBareJid != nil && e.rosterItem != nil else {
                return;
            }
            guard e.sessionObject.userBareJid! == self.account && e.rosterItem!.jid.bareJid == self.jid.bareJid else {
                return;
            }
            DispatchQueue.main.async {
                self.titleView.name = e.rosterItem!.name ?? e.rosterItem!.jid.stringValue;
            }
        default:
            break;
        }
    }
    
    @objc func newMessage(_ notification: NSNotification) {
        guard ((notification.userInfo!["account"] as? BareJID) == account) && ((notification.userInfo!["sender"] as? BareJID) == jid.bareJid) else {
            return;
        }
        
        let ts: Date = notification.userInfo!["timestamp"] as! Date;
        let msgId: Int = notification.userInfo!["msgId"] as! Int;
//        guard notification.userInfo?["fromArchive"] as? Bool ?? false == false else {
//            if !self.syncInProgress {
//                cachedDataSource.reset();
//                tableView.reloadData();
//            }
//            return;
//        }
        
        //DispatchQueue.main.async {
        self.newItemAdded(id: msgId, timestamp: ts);
        //}

        if let state = notification.userInfo?["state"] as? DBChatHistoryStore.State {
            if state == .incoming_unread || state == .incoming_error_unread {
                self.xmppService.dbChatHistoryStore.markAsRead(for: account, with: jid.bareJid);
            }
        }
    }
    
    @objc func avatarChanged(_ notification: NSNotification) {
        guard ((notification.userInfo?["jid"] as? BareJID) == jid.bareJid) else {
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
    
    @objc func messageUpdated(_ notification: Notification) {
        guard let data = notification.userInfo else {
            return;
        }
        guard let id = data["message-id"] as? Int else {
            return;
        }
        updateItem(msgId: id) { (item) in
            if let state = data["state"] as? DBChatHistoryStore.State {
                (item as? ChatViewItem)?.state = state;
                if state == DBChatHistoryStore.State.outgoing_error_unread {
                    DispatchQueue.global(qos: .background).async {
                        self.xmppService.dbChatHistoryStore.markAsRead(for: self.account, with: self.jid.bareJid);
                    }
                }
            }
            if data.keys.contains("preview") {
                (item as? ChatViewItem)?.preview = data["preview"] as? String;
            }
        }
    }
    
    @objc func chatChanged(_ notification: Notification) {
        guard let chat = notification.object as? DBChat else {
            return;
        }
        guard self.account == chat.account && self.jid.bareJid == chat.jid.bareJid else {
            return;
        }
        
        self.chat = chat;
        
        titleView.encryption = chat.options.encryption;//(notification.userInfo?["encryption"] as? ChatEncryption) ?? .none;
    }
    
    fileprivate func updateTitleView() {
        let state = xmppService.getClient(forJid: self.account)?.state;

        titleView.reload(for: self.account, with: self.jid.bareJid);

        DispatchQueue.main.async {
            self.titleView.connected = state != nil && state == .connected;
        }
        #if targetEnvironment(simulator)
        #else
        let jingleSupported = JingleManager.instance.support(for: self.jid.withoutResource, on: self.account);
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
        VideoCallController.call(jid: self.jid.bareJid, from: self.account, withAudio: true, withVideo: false, sender: self);
    }
    
    @objc func videoCall() {
        VideoCallController.call(jid: self.jid.bareJid, from: self.account, withAudio: true, withVideo: true, sender: self);
    }
    #endif
    
    @objc func refreshChatHistory() {
        let syncPeriod = AccountSettings.MessageSyncPeriod(account.stringValue).getDouble();
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
        
        mamModule.queryItems(with: jid, start: start, queryId: "sync-2", rsm: rsmQuery ?? RSM.Query(lastItems: 100), onSuccess: {(queryid,complete,rsmResponse) in
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
        let client = xmppService.getClient(forJid: account);
        if client != nil && client!.state == .connected {
            let encryption = self.titleView.encryption ?? ChatEncryption(rawValue: Settings.MessageEncryption.getString() ?? "") ?? .none
            DispatchQueue.global(qos: .default).async {
                switch encryption {
                case .none:
                    self.sendUnencryptedMessage(body: body, url: url, completionHandler: { (message) in
                        completed?();
                    });
                case .omemo:
                    self.sendEncryptedMessage(body: body, url: url, completionHandler: { (message) in
                        completed?();
                    });
                }
            }
        } else {
            var alert: UIAlertController? = nil;
            if client == nil {
                alert = UIAlertController.init(title: "Warning", message: "Account is disabled.\nDo you want to enable account?", preferredStyle: .alert);
                alert?.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                alert?.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                    if let account = AccountManager.getAccount(forJid: self.account.stringValue) {
                        account.active = true;
                        AccountManager.updateAccount(account);
                    }
                }));
            } else if client?.state != .connected {
                alert = UIAlertController.init(title: "Warning", message: "Account is disconnected.\nPlease wait until account will reconnect", preferredStyle: .alert);
                alert?.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            }
            if alert != nil {
                self.present(alert!, animated: true, completion: nil);
            }
        }
    }
    
    fileprivate func sendUnencryptedMessage(body: String, url: String?, completionHandler: @escaping (Message)->Void) {
        guard let (message, messageModule) = createMessage(body: body, url: url) else {
            return;
        }
        
        messageModule.context.writer?.write(message);

        self.xmppService.dbChatHistoryStore.appendEntry(for: account, jid: jid!.bareJid, state: .outgoing, authorJid: account, data: body, timestamp: Date(), id: message.id, encryption: .none, encryptionFingerprint: nil, fromArchive: false, carbonAction: nil, nicknameInRoom: nil) { msgId in
            completionHandler(message);
        }
    }
    
    fileprivate func sendEncryptedMessage(body: String, url: String?, completionHandler: @escaping (Message)->Void) {
        guard let (message, messageModule) = createMessage(body: body) else {
            return;
        }
        
        let account = self.account!;
        let jid = self.jid!;

        guard let omemoModule: OMEMOModule = XmppService.instance.getClient(forJid: account)?.modulesManager.getModule(OMEMOModule.ID) else {
            print("NO OMEMO MODULE!");
            return;
        }
        let completionHandler: ((EncryptionResult<Message, SignalError>)->Void) = { (result) in
            switch result {
            case .failure(let error):
                switch error {
                case .noSession:
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Could not send a message", message: "It was not possible to send encrypted message as there is no trusted device.\n\nWould you like to disable encryption for this chat and send a message?", preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                        alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { action in
                            self.chat?.modifyOptions({ (options) in
                                options.encryption = .none;
                            }) {
                                DispatchQueue.main.async {
                                    self.sendUnencryptedMessage(body: body, url: url, completionHandler: completionHandler);
                                }
                            }
                        }))
                        self.present(alert, animated: true, completion: nil);
                    }
                default:
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Could not send a message", message: "It was not possible to send encrypted message due to encryption error", preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                        self.present(alert, animated: true, completion: nil);
                    }
                }
                break;
            case .successMessage(let encryptedMessage, let fingerprint):
                self.xmppService.dbChatHistoryStore.appendEntry(for: account, jid: jid.bareJid, state: .outgoing, authorJid: account, data: body, timestamp: Date(), id: encryptedMessage.id, encryption: .decrypted, encryptionFingerprint: fingerprint, fromArchive: false, carbonAction: nil, nicknameInRoom: nil) { msgId in
                    completionHandler(encryptedMessage);
                }
            }
        };
        
        omemoModule.send(message: message, completionHandler: completionHandler);
    }
    
    fileprivate func createMessage(body: String, url: String? = nil) -> (Message, MessageModule)? {
        guard let messageModule: MessageModule = XmppService.instance.getClient(forJid: account)?.modulesManager.getModule(MessageModule.ID) else {
            return nil;
        }
        
        guard let chat = messageModule.chatManager.getChat(with: jid, thread: nil) else {
            return nil;
        }
        
        let message = chat.createMessage(body);
        if url != nil {
            message.oob = url;
        }
        if Settings.MessageDeliveryReceiptsEnabled.getBool() {
            message.messageDelivery = MessageDeliveryReceiptEnum.request;
        }
        if message.id == nil {
            message.id = UUID().uuidString;
        }
        return (message, messageModule);
    }
    
    class ChatDataSource: CachedViewDataSource<ChatViewItem> {
        
        fileprivate let getMessagesStmt: DBStatement!;

        weak var controller: ChatViewController?;
        
        init(controller: ChatViewController) {
            self.controller = controller;
            self.getMessagesStmt = controller.xmppService.dbChatHistoryStore.getMessagesStatementForAccountAndJid();
        }
        
        override func getItemsCount() -> Int {
            return controller!.xmppService.dbChatHistoryStore.countMessages(for: controller!.account, with: controller!.jid.bareJid);
        }
        
        override func loadData(afterMessageWithId msgId: Int?, offset: Int, limit: Int, forEveryItem: (Int, ChatViewItem)->Void) {
            controller!.xmppService.dbChatHistoryStore.msgAlreadyAddedStmt.dispatcher.sync {
                let position = msgId != nil
                    ? controller!.xmppService.dbChatHistoryStore.getMessagePosition(for: controller!.account, with: controller!.jid.bareJid, msgId: msgId!, inverted: true)
                    : 0;
                var off = position + offset;
                if off < 0 {
                    off = 0;
                }
                var idx = 0
                controller!.xmppService.dbChatHistoryStore.forEachMessage(stmt: getMessagesStmt, account: controller!.account, jid: controller!.jid.bareJid, limit: limit,
                                                                          offset: off, forEach: { (cursor)-> Void in
                    forEveryItem(idx, ChatViewItem(cursor: cursor));
                    idx = idx + 1;
                });
            }
        }
        
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
            let encryption = self.encryption ?? ChatEncryption(rawValue: Settings.MessageEncryption.getString() ?? "") ?? .none;
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
