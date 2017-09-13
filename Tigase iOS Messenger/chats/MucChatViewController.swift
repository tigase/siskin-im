//
// MucChatViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

class MucChatViewController: BaseChatViewController, CachedViewControllerProtocol, UITableViewDataSource, EventHandler, BaseChatViewController_ShareImageExtension, BaseChatViewController_PreviewExtension {

    var titleView: MucTitleView!;
    var room: Room?;

    let log: Logger = Logger();
    var scrollToIndexPath: IndexPath? = nil;

    var dataSource: MucChatDataSource!;
    var cachedDataSource: CachedViewDataSourceProtocol {
        return dataSource as CachedViewDataSourceProtocol;
    }

    @IBOutlet var shareButton: UIButton!;
    @IBOutlet var progressBar: UIProgressView!;
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?;

    override func viewDidLoad() {
        dataSource = MucChatDataSource(controller: self);
        scrollDelegate = self;
        super.viewDidLoad()
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

        self.navigationItem.titleView = titleView;
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
        let item: MucChatViewItem = dataSource.getItem(for: indexPath);

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
        let id = incoming ? "MucChatTableViewCellIncoming" : "MucChatTableViewCellOutgoing"

        let cell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! MucChatTableViewCell;
        cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
        cell.nicknameLabel?.text = item.nickname;
        if item.authorJid != nil {
            cell.avatarView?.image = self.xmppService.avatarManager.getAvatar(for: item.authorJid!, account: self.account);
        } else {
            cell.avatarView?.image = self.xmppService.avatarManager.defaultAvatar;
        }
        cell.setValues(data: item.data, ts: item.timestamp, id: item.id, state: state, preview: item.preview, downloader: self.downloadPreview);
        return cell;
    }


    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOccupants" {
            if let navigation = segue.destination as? UINavigationController {
                if let occupantsController = navigation.visibleViewController as? MucChatOccupantsTableViewController {
                    occupantsController.room = room;
                    occupantsController.account = account;
                }
            }
        }
    }

    func newMessage(_ notification: NSNotification) {
        guard ((notification.userInfo?["account"] as? BareJID) == account) && ((notification.userInfo?["sender"] as? BareJID) == jid.bareJid) else {
            return;
        }

        self.newItemAdded(timestamp: notification.userInfo!["timestamp"] as! Date);
        xmppService.dbChatHistoryStore.markAsRead(for: account, with: jid.bareJid);
    }

    func avatarChanged(_ notification: NSNotification) {
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

    func accountStateChanged(_ notification: Notification) {
        let account = notification.userInfo!["account"]! as! String;
        if self.account.stringValue == account {
            updateTitleView();
        }
    }

    fileprivate func updateTitleView() {
        let state = xmppService.getClient(forJid: self.account)?.state;
        DispatchQueue.main.async {
            self.titleView.connected = state != nil && state == .connected;
        }
    }

    func updateItem(msgId: Int, handler: @escaping (BaseChatViewController_PreviewExtension_PreviewAwareItem) -> Void) {
        DispatchQueue.main.async {
//            self.dataSource.reset();
//            self.tableView.reloadData();
            if let indexPath = self.dataSource.getIndexPath(withId: msgId) {
                let item = self.dataSource.getItem(for: indexPath);
                handler(item);
                self.tableView.reloadRows(at: [indexPath], with: .automatic);
            }
        }
    }

    @IBAction func sendClicked(_ sender: UIButton) {
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

        self.sendMessage(body: text!, additional: [], completed: {() in
            DispatchQueue.main.async {
                self.messageText = nil;
            }
        });
    }

    @IBAction func shareClicked(_ sender: UIButton) {
        self.showPhotoSelector(sender);
    }

    func sendMessage(body: String, additional: [Element], preview: String? = nil, completed: (()->Void)?) {
        self.room!.sendMessage(body, additionalElements: additional);
        completed?();
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

        override func loadData(offset: Int, limit: Int, forEveryItem: (MucChatViewItem)->Void) {
            controller!.xmppService.dbChatHistoryStore.forEachMessage(stmt: getMessagesStmt, account: controller!.account, jid: controller!.jid.bareJid, limit: limit, offset: offset, forEach: { (cursor)-> Void in
                forEveryItem(MucChatViewItem(cursor: cursor));
            });
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
