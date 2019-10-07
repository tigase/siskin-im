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

class MucChatViewController: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar, UITableViewDataSource, BaseChatViewController_ShareImageExtension, BaseChatViewController_PreviewExtension {

    static let MENTION_OCCUPANT = Notification.Name("groupchatMentionOccupant");
    
    var titleView: MucTitleView! {
        get {
            return self.navigationItem.titleView as! MucTitleView;
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

    @IBOutlet var shareButton: UIButton!;
    @IBOutlet var progressBar: UIProgressView!;
    var imagePickerDelegate: BaseChatViewController_ShareImagePickerDelegate?;
    var filePickerDelegate: BaseChatViewController_ShareFilePickerDelegate?;

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        let mucModule: MucModule? = xmppService.getClient(forJid: account)?.modulesManager?.getModule(MucModule.ID);
        room = mucModule?.roomsManager.getRoom(for: jid) as? DBRoom;
        navigationItem.title = room?.name ?? jid.stringValue;
        
        titleView.name = navigationItem.title;
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(MucChatViewController.roomInfoClicked));
        self.titleView.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);

        tableView.dataSource = self;
        tableView.delegate = self;
        
        initSharing();
        
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

    // MARK: - Table view data source

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count;
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let dbItem = dataSource.getItem(at: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "MucChatTableViewCellIncoming", for: indexPath);
        }
        
        switch dbItem {
        case let item as ChatMessage:
            var continuation = false;
            if Settings.EnableNewUI.getBool() && (indexPath.row + 1) < dataSource.count {
                if let prevItem = dataSource.getItem(at:  indexPath.row + 1) {
                    continuation = item.isMergeable(with: prevItem);
                }
            }
                    
            let id = Settings.EnableNewUI.getBool() ? (continuation ? "MucChatTableViewCellContinuation" : "MucChatTableViewCell") : (item.state.direction == .incoming ? "MucChatTableViewCellIncoming" : "MucChatTableViewCellOutgoing")

            let cell = tableView.dequeueReusableCell(withIdentifier: id, for: indexPath) as! ChatTableViewCell;
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            //        cell.nicknameLabel?.text = item.nickname;
            if item.authorJid != nil {
                cell.avatarView?.updateAvatar(manager: AvatarManager.instance, for: self.account, with: item.authorJid!, name: item.authorNickname, orDefault: AvatarManager.instance.defaultGroupchatAvatar);
            } else {
                cell.avatarView?.image = self.xmppService.avatarManager.defaultAvatar;
            }
            cell.nicknameView?.text = item.authorNickname;
            cell.set(message: item, downloader: downloadPreview(url:msgId:account:jid:));
            cell.backgroundColor = Appearance.current.systemBackground;
            return cell;
        case let item as SystemMessage:
            let cell: ChatTableViewSystemCell = tableView.dequeueReusableCell(withIdentifier: "MucChatTableViewSystemCell", for: indexPath) as! ChatTableViewSystemCell;
            cell.set(item: item);
            cell.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
            return cell;
        default:
            return tableView.dequeueReusableCell(withIdentifier: "MucChatTableViewCellIncoming", for: indexPath);
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
    }

    @objc func avatarChanged(_ notification: NSNotification) {
        // TODO: adjust this to make it work properly with MUC
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

    fileprivate func updateTitleView() {
        let state = xmppService.getClient(forJid: self.account)?.state;
        DispatchQueue.main.async {
            self.titleView.connected = state != nil && state == .connected;
            self.titleView.nameView.textColor = Appearance.current.navigationBarTextColor;
            self.titleView.statusView.textColor = Appearance.current.navigationBarTextColor;
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

    @objc func roomInfoClicked() {
        print("room info for", account, room?.roomJid, "clicked!");
        guard let settingsController = self.storyboard?.instantiateViewController(withIdentifier: "MucChatSettingsViewController") as? MucChatSettingsViewController else {
            return;
        }
        settingsController.account = self.account;
        settingsController.room = self.room as? DBRoom;
        
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

    func refreshRoomInfo(_ room: Room) {
        titleView.state = room.state;
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
