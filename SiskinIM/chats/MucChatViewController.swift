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

class MucChatViewController: BaseChatViewControllerWithContextMenuAndToolbar, BaseChatViewControllerWithContextMenuAndToolbarDelegate, CachedViewControllerProtocol, UITableViewDataSource, EventHandler, BaseChatViewController_ShareImageExtension, BaseChatViewController_PreviewExtension {

    static let MENTION_OCCUPANT = Notification.Name("groupchatMentionOccupant");
    
    var titleView: MucTitleView!;
    var room: Room?;

    let log: Logger = Logger();

    var dataSource: MucChatDataSource!;
    var cachedDataSource: CachedViewDataSourceProtocol {
        return dataSource as CachedViewDataSourceProtocol;
    }

    @IBOutlet var shareButton: UIButton!;
    @IBOutlet var progressBar: UIProgressView!;
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?;

        lazy var loadChatInfo:DBStatement! = try? self.dbConnection.prepareStatement("SELECT name FROM chats WHERE account = :account AND jid = :jid");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let params:[String:Any?] = ["account" : account, "jid" : jid.bareJid];
        navigationItem.title = try! loadChatInfo.findFirst(params) { cursor in cursor["name"] } ?? jid.stringValue;

        dataSource = MucChatDataSource(controller: self);
        contextMenuDelegate = self;
        scrollDelegate = self;
        initialize();
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        let mucModule: MucModule? = xmppService.getClient(forJid: account)?.modulesManager?.getModule(MucModule.ID);
        room = mucModule?.roomsManager.getRoom(for: jid.bareJid);

        tableView.dataSource = self;

        let navBarHeight = self.navigationController!.navigationBar.frame.size.height;
        let width = CGFloat(220);

        titleView = MucTitleView(width: width, height: navBarHeight);
        titleView.name = navigationItem.title;

        let roomBtn = UIButton(type: .system);
        roomBtn.frame = CGRect(x: 0, y: 0, width: width, height: navBarHeight);
        roomBtn.addSubview(titleView);
        
        roomBtn.addTarget(self, action: #selector(MucChatViewController.roomInfoClicked(_:)), for: .touchDown);
        self.navigationItem.titleView = roomBtn;
        
        initSharing();
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        xmppService.registerEventHandler(self, for: MucModule.YouJoinedEvent.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
        NotificationCenter.default.addObserver(self, selector: #selector(MucChatViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(MucChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil)

        self.updateTitleView();
        refreshRoomInfo(room!);
    }

    override func viewDidDisappear(_ animated: Bool) {
        xmppService.unregisterEventHandler(self, for: MucModule.YouJoinedEvent.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
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
        return dataSource.numberOfMessages;
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item: MucChatViewItem = dataSource.getItem(for: indexPath) else {
            return tableView.dequeueReusableCell(withIdentifier: "MucChatTableViewCellIncoming", for: indexPath)
        }

        var continuation = false;
        if Settings.EnableNewUI.getBool() && (indexPath.row + 1) < dataSource.numberOfMessages {
            if let prevItem = dataSource.getItem(for: IndexPath(row: indexPath.row + 1, section: 0)) {
                continuation = prevItem.state.direction == item.state.direction && (abs(item.timestamp.timeIntervalSince(prevItem.timestamp)) < 30.0);
            }
        }
        let incoming = item.nickname != self.room?.nickname;
        var state = item.state!;
        if !incoming {
            switch state {
            case .incoming_error:
                state = .outgoing_error;
            case .incoming_error_unread:
                state = .outgoing_error_unread;
            default:
                state = .outgoing_delivered;
            }
        }
        
        let id = Settings.EnableNewUI.getBool() ? (continuation ? "MucChatTableViewCellContinuation" : "MucChatTableViewCell") : (incoming ? "MucChatTableViewCellIncoming" : "MucChatTableViewCellOutgoing")

        let cell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
        cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
//        cell.nicknameLabel?.text = item.nickname;
        if item.authorJid != nil {
            cell.avatarView?.updateAvatar(manager: self.xmppService.avatarManager, for: self.account, with: item.authorJid!, name: item.nickname, orDefault: self.xmppService.avatarManager.defaultGroupchatAvatar);
        } else {
            cell.avatarView?.image = self.xmppService.avatarManager.defaultAvatar;
        }
        cell.setValues(data: item.data, ts: item.timestamp, id: item.id, nickname: item.nickname, state: state, preview: item.preview, downloader: self.downloadPreview);
        cell.backgroundColor = Appearance.current.tableViewCellBackgroundColor();
        return cell;
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
    }
    
    func getTextOfSelectedRows(paths: [IndexPath], withTimestamps: Bool, handler: (([String]) -> Void)?) {
        let items: [MucChatViewItem] = paths.map({ index in dataSource.getItem(for: index) }).filter({ (it) -> Bool in
            it != nil;
        }).map({ it -> MucChatViewItem in it! })
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
        
        let withoutPrefix = Set(items.map({it in it.nickname ?? it.authorJid?.stringValue ?? ""})).count == 1;
        
        let formatter = DateFormatter();
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy jj:mm", options: 0, locale: NSLocale.current);
        
        var prevSender: String = "";
        let texts = items.map { (it) -> String in
            if withoutPrefix {
                if withTimestamps {
                    return "[\(formatter.string(from: it.timestamp))] \(it.data ?? "")"
                } else {
                    return it.data ?? "";
                }
            } else {
                let sender = it.nickname ?? it.authorJid?.stringValue ?? "";
                let prefix = (prevSender != sender) ?
                    "\(it.state.direction == .incoming ? sender : "Me"):\n" : "";
                prevSender = sender;
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

    @objc func newMessage(_ notification: NSNotification) {
        guard ((notification.userInfo!["account"] as? BareJID) == account) && ((notification.userInfo!["sender"] as? BareJID) == jid.bareJid) else {
            return;
        }

        let msgId = notification.userInfo!["msgId"] as! Int;
        self.newItemAdded(id: msgId, timestamp: notification.userInfo!["timestamp"] as! Date);
        xmppService.dbChatHistoryStore.markAsRead(for: account, with: jid.bareJid);
    }

    @objc func avatarChanged(_ notification: NSNotification) {
        // TODO: adjust this to make it work properly with MUC
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
            updateTitleView();
        }
    }

    fileprivate func updateTitleView() {
        let state = xmppService.getClient(forJid: self.account)?.state;
        DispatchQueue.main.async {
            self.titleView.connected = state != nil && state == .connected;
            self.titleView.nameView.textColor = Appearance.current.navigationBarTextColor();
            self.titleView.statusView.textColor = Appearance.current.navigationBarTextColor();
        }
    }

    func updateItem(msgId: Int, handler: @escaping (BaseChatViewController_PreviewExtension_PreviewAwareItem) -> Void) {
        DispatchQueue.main.async {
//            self.dataSource.reset();
//            self.tableView.reloadData();
            if let indexPath = self.dataSource.getIndexPath(withId: msgId) {
                if let item = self.dataSource.getItem(for: indexPath) {
                    handler(item);
                    self.tableView.reloadRows(at: [indexPath], with: .automatic);
                }
            }
        }
    }

    @IBAction func sendClicked(_ sender: UIButton) {
        self.sendMessage();
    }

    override func sendMessage() {
        let text = messageText;
        guard !(text?.isEmpty != false) else {
            return;
        }
        
        guard room?.state == .joined else {
            let alert: UIAlertController?  = UIAlertController.init(title: "Warning", message: "You are not connected to room.\nPlease wait reconnection to room", preferredStyle: .alert);
            alert?.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.present(alert!, animated: true, completion: nil);
            return;
        }
        
        self.sendMessage(body: text!, url: nil, completed: {() in
            DispatchQueue.main.async {
                self.messageText = nil;
            }
        });
    }
    
    @IBAction func shareClicked(_ sender: UIButton) {
        self.showPhotoSelector(sender);
    }

    func sendMessage(body: String, url: String? = nil, preview: String? = nil, completed: (()->Void)?) {
        self.room!.sendMessage(body, url: url, additionalElements: []);
        completed?();
    }

    @objc func roomInfoClicked(_ sender: UIButton) {
        print("room info for", account, room?.roomJid, "clicked!");
        guard let settingsController = self.storyboard?.instantiateViewController(withIdentifier: "MucChatSettingsViewController") as? MucChatSettingsViewController else {
            return;
        }
        settingsController.account = self.account;
        settingsController.room = self.room as? DBRoom;
        
        self.navigationController?.pushViewController(settingsController, animated: true);
    }
    
    func handle(event: Event) {
        switch event {
        case let e as MucModule.JoinRequestedEvent:
            DispatchQueue.main.async {
                self.refreshRoomInfo(e.room);
            }
        case let e as MucModule.YouJoinedEvent:
            DispatchQueue.main.async {
                self.refreshRoomInfo(e.room);
            }
        case let e as MucModule.RoomClosedEvent:
            DispatchQueue.main.async {
                self.refreshRoomInfo(e.room);
            }
        default:
            break;
        }
    }

    func refreshRoomInfo(_ room: Room) {
        titleView.state = room.state;
    }
    
    class MucChatDataSource: CachedViewDataSource<MucChatViewItem> {

        fileprivate let getMessagesStmt: DBStatement!;

        weak var controller: MucChatViewController?;

        init(controller: MucChatViewController) {
            self.controller = controller;
            self.getMessagesStmt = controller.xmppService.dbChatHistoryStore.getMessagesStatementForAccountAndJid();
        }

        override func getItemsCount() -> Int {
            return controller!.xmppService.dbChatHistoryStore.countMessages(for: controller!.account, with: controller!.jid.bareJid);
        }

        override func loadData(afterMessageWithId msgId: Int?, offset: Int, limit: Int, forEveryItem: (Int, MucChatViewItem)->Void) {
            controller!.xmppService.dbChatHistoryStore.msgAlreadyAddedStmt.dispatcher.sync {
                let position = msgId != nil
                    ? controller!.xmppService.dbChatHistoryStore.getMessagePosition(for: controller!.account, with: controller!.jid.bareJid, msgId: msgId!, inverted: true)
                    : 0;
                var off = position + offset;
                if off < 0 {
                    off = 0;
                }
                var idx = 0;
                controller!.xmppService.dbChatHistoryStore.forEachMessage(stmt: getMessagesStmt, account: controller!.account, jid: controller!.jid.bareJid, limit: limit,
                                                                          offset: off, forEach: { (cursor)-> Void in
                                                                            forEveryItem(idx, MucChatViewItem(cursor: cursor));
                                                                            idx = idx + 1;
                });
            }
        }
    }

    open class MucChatViewItem: CachedViewDataSourceItem, BaseChatViewController_PreviewExtension_PreviewAwareItem {
        let id: Int;
        let nickname: String?;
        let timestamp: Date;
        let data: String?;
        let authorJid: BareJID?;
        var preview: String?;
        let state: DBChatHistoryStore.State!;

        init(cursor: DBCursor) {
            id = cursor["id"]!;
            nickname = cursor["author_nickname"];
            timestamp = cursor["timestamp"]!;
            data = cursor["data"];
            authorJid = cursor["author_jid"];
            preview = cursor["preview"];
            state = DBChatHistoryStore.State(rawValue: cursor["state"]!)!;
        }

    }

    class MucTitleView: UIView {

        let nameView: UILabel!;
        let statusView: UILabel!;
        let statusHeight: CGFloat!;

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

        init(width: CGFloat, height: CGFloat) {
            let spacing = (height * 0.23) / 3;
            statusHeight = height * 0.32;
            nameView = UILabel(frame: CGRect(x: 0, y: spacing, width: width, height: height * 0.48));
            statusView = UILabel(frame: CGRect(x: 0, y: (height * 0.44) + (spacing * 2), width: width, height: statusHeight));
            super.init(frame: CGRect(x: 0, y: 0, width: width, height: height));


            var font = nameView.font;
            font = font?.withSize((font?.pointSize)!);
            nameView.font = font;
            nameView.textAlignment = .center;
            nameView.adjustsFontSizeToFitWidth = true;

            font = statusView.font;
            font = font?.withSize((font?.pointSize)! - 5);
            statusView.font = font;
            statusView.textAlignment = .center;
            statusView.adjustsFontSizeToFitWidth = true;

            self.isUserInteractionEnabled = false;

            self.addSubview(nameView);
            self.addSubview(statusView);
        }

        required init?(coder aDecoder: NSCoder) {
            statusHeight = nil;
            statusView = nil;
            nameView = nil;
            super.init(coder: aDecoder);
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
                statusIcon.bounds = CGRect(x: 0, y: -3, width: statusHeight, height: statusHeight);

                let statusText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: statusIcon));
                statusText.append(NSAttributedString(string: desc));
                statusView.attributedText = statusText;
            } else {
                statusView.text = "\u{26A0} Not connected!";
            }
        }
    }

}
