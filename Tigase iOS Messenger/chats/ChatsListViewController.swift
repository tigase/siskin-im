//
// ChatListViewController.swift
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

class ChatsListViewController: UITableViewController, EventHandler {
    var dbConnection:DBConnection {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.dbConnection;
    }
    var xmppService:XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    @IBOutlet var addMucButton: UIBarButtonItem!
    
    fileprivate lazy var countChats:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) AS count FROM chats");
    fileprivate lazy var getChat:DBStatement! = try? self.dbConnection.prepareStatement("SELECT jid, account, timestamp, thread_id, type, (SELECT data FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND item_type = 0 ORDER BY timestamp DESC LIMIT 1) AS last_message, (SELECT count(ch.id) FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND state = 2) as unread, (SELECT name FROM roster_items ri WHERE ri.account = c.account AND ri.jid = c.jid) as name FROM chats as c ORDER BY timestamp DESC LIMIT 1 OFFSET :offset");
    fileprivate lazy var getChatTimestampFromHistoryByAccountAndJidStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT timestamp FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp DESC LIMIT 1 OFFSET :offset")
    fileprivate lazy var getChatTimestampByAccountAndJidStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT timestamp FROM chats WHERE account = :account AND jid = :jid")
    fileprivate lazy var getChatPositionByTimestampStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM chats WHERE timestamp > :timestamp");
    fileprivate lazy var getChatPositionByChatIdStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM chats WHERE timestamp > (SELECT timestamp FROM chats WHERE id = :id)");
    
    var closingChatPosition:Int? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.rowHeight = 66.0;//UITableViewAutomaticDimension;
        //tableView.estimatedRowHeight = 66.0;
        tableView.dataSource = self;
//        tableView.separatorStyle = .;
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        updateBadge();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        tableView.reloadData();
        xmppService.registerEventHandler(self, events: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
        //(self.tabBarController as? CustomTabBarController)?.showTabBar();
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, events: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
        NotificationCenter.default.removeObserver(self, name: AvatarManager.AVATAR_CHANGED, object: nil);
    }

    deinit {
        NotificationCenter.default.removeObserver(self);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return try! countChats.scalar() ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "ChatsListTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! ChatsListTableViewCell;
        
        let params:[String:Any?] = ["offset": indexPath.row];
        do {
            try getChat.query(params) { (cursor)->Void in
                let account: BareJID = cursor["account"]!;
                let jid: BareJID = cursor["jid"]!;
                let name:String? = cursor["name"];
                let unread = cursor["unread"] ?? 0;
                let type: Int = cursor["type"] ?? 0;
                
                cell.nameLabel.text = name ?? jid.stringValue;
                let last_message: String? = cursor["last_message"];
                cell.lastMessageLabel.text = last_message == nil ? nil : ((unread > 0 ? "" : "\u{2713}") + last_message!);
                let formattedTS = self.formatTimestamp(cursor["timestamp"]!);
                cell.timestampLabel.text = formattedTS;

                let xmppClient = self.xmppService.getClient(account);
                switch type {
                case 1:
                    let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
                    cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.defaultAvatar);
                    cell.avatarStatusView.setStatus(mucModule?.roomsManager.get(jid)?.state == .joined ? Presence.Show.online : nil);
                default:
                    cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.getAvatar(jid, account: account));
                    let presenceModule: PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                    let presence = presenceModule?.presenceStore.getBestPresence(jid);
                    cell.avatarStatusView.setStatus(presence?.show);
                }
            }
        } catch _ {
            cell.nameLabel.text = "DBError";
        }
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if (indexPath.section == 0) {
            return true;
        }
        return false;
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCellEditingStyle.delete {
            if indexPath.section == 0 {
                do {
                    let params:[String:Any?] = ["offset": indexPath.row];
                    try getChat.query(params) { (cursor)->Void in
                        let account: BareJID = cursor["account"]!;
                        let jid: JID = cursor["jid"]!;
                        let type: Int = cursor["type"] ?? 0;
                        let xmppClient = self.xmppService.getClient(account);

                        switch type {
                        case 1:
                            let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
                            if let room = mucModule?.roomsManager.get(jid.bareJid) {
                                self.closingChatPosition = try! self.getChatPositionByChatIdStmt.scalar(room.id!);
                                mucModule?.leave(room);
                                self.closingChatPosition = nil;
                                if Settings.DeleteChatHistoryOnChatClose.getBool() {
                                    self.xmppService.dbChatHistoryStore.deleteMessages(account, jid: jid.bareJid);
                                } else {
                                    self.xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
                                }
                            }
                        default:
                            let thread: String? = cursor["thread_id"];
                            let messageModule: MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                            if let chat = messageModule?.chatManager.getChat(jid, thread: thread) {
                                self.closingChatPosition = try! self.getChatPositionByChatIdStmt.scalar(chat.id!);
                                messageModule?.chatManager.close(chat);
                                self.closingChatPosition = nil;
                                if Settings.DeleteChatHistoryOnChatClose.getBool() {
                                    self.xmppService.dbChatHistoryStore.deleteMessages(account, jid: jid.bareJid);
                                } else {
                                    self.xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
                                }
                            }
                        }
                    }
                } catch _ {
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
        do {
            let params:[String:Any?] = ["offset": indexPath.row];
            try getChat.query(params) { (cursor)->Void in
                let type: Int = cursor["type"]!;
                let account: BareJID = cursor["account"]!;
                let jid: JID = cursor["jid"]!;
                
                var identifier: String!;
                switch type {
                case 1:
                    identifier = "RoomViewNavigationController";
                    let client = self.xmppService.getClient(account);
                    let mucModule: MucModule? = client?.modulesManager?.getModule(MucModule.ID);
                    let room = mucModule?.roomsManager.get(jid.bareJid);
                    guard room != nil else {
                        if client == nil {
                            let alert = UIAlertController.init(title: "Warning", message: "Account is disabled.\nDo you want to enable account?", preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                                if let accountInstance = AccountManager.getAccount(account.stringValue) {
                                    accountInstance.active = true;
                                    AccountManager.updateAccount(accountInstance);
                                }
                            }));
                        }
                        return;
                    }
                default:
                    identifier = "ChatViewNavigationController";
                }
                
                let controller = self.storyboard?.instantiateViewController(withIdentifier: identifier);
                let navigationController = controller as? UINavigationController;
                let destination = navigationController?.visibleViewController ?? controller;
                
                if let baseChatViewController = destination as? BaseChatViewController {
                    baseChatViewController.account = account;
                    baseChatViewController.jid = jid;
                }
                destination?.hidesBottomBarWhenPushed = true;
                
                if controller != nil {
                    self.showDetailViewController(controller!, sender: self);
                }
            }
        } catch _ {
        }
        
    }

    @IBAction func addMucButtonClicked(_ sender: UIBarButtonItem) {
        print("add MUC button clicked");
        let navigation = storyboard?.instantiateViewController(withIdentifier: "MucJoinNavigationController") as! UINavigationController;
        self.showDetailViewController(navigation, sender: self);
    }
    
    func handleEvent(_ event: Event) {
        switch event {
        case is MessageModule.ChatCreatedEvent:
            // we are adding rows always on top
            let index = IndexPath(row: 0, section: 0);
            DispatchQueue.main.sync() {
                self.tableView.insertRows(at: [index], with: .fade);
            }
            // if above is not working we can reload
            //tableView.reloadData();
        case is MessageModule.ChatClosedEvent:
            // we do not know position of chat which was closed
            //tableView.reloadData();
            DispatchQueue.main.sync() {
                if self.closingChatPosition != nil {
                    let indexPath = IndexPath(row: self.closingChatPosition!, section: 0);
                    self.tableView.deleteRows(at: [indexPath], with: .fade);
                } else {
                    self.tableView.reloadData();
                }
            }
        case let e as PresenceModule.ContactPresenceChanged:
            //tableView.reloadData();
            guard e.sessionObject.userBareJid != nil, let from = e.presence.from else {
                // guard for possible malformed presence
                return;
            }
            DispatchQueue.main.async() {
                let timestamp: Date? = try! self.getChatTimestampByAccountAndJidStmt.query(e.sessionObject.userBareJid!, from.bareJid)?["timestamp"];
                if timestamp != nil && timestamp?.timeIntervalSince1970 != 0 {
                    let pos = try! self.getChatPositionByTimestampStmt.scalar(timestamp!);
                    let indexPath = IndexPath(row: pos!, section: 0);
                    self.tableView.reloadRows(at: [indexPath], with: .automatic);
                }
            }
        case is MucModule.JoinRequestedEvent:
            let index = IndexPath(row: 0, section: 0);
            DispatchQueue.main.sync() {
                self.tableView.insertRows(at: [index], with: .fade);
            }
        case let e as MucModule.YouJoinedEvent:
            DispatchQueue.main.async() {
                let timestamp: Date? = try! self.getChatTimestampByAccountAndJidStmt.query(e.sessionObject.userBareJid, e.room.roomJid)?["timestamp"];
                if timestamp != nil && timestamp?.timeIntervalSince1970 != 0 {
                    let pos = try! self.getChatPositionByTimestampStmt.scalar(timestamp!);
                    let indexPath = IndexPath(row: pos!, section: 0);
                    self.tableView.reloadRows(at: [indexPath], with: .automatic);
                }
            }
        case is MucModule.RoomClosedEvent:
            DispatchQueue.main.sync() {
                if self.closingChatPosition != nil {
                    let indexPath = IndexPath(row: self.closingChatPosition!, section: 0);
                    self.tableView.deleteRows(at: [indexPath], with: .fade);
                } else {
                    self.tableView.reloadData();
                }
            }
        default:
            break;
        }
    }
    
    func newMessage(_ notification:NSNotification) {
        if navigationController?.visibleViewController == self {
//            tableView.reloadData();
            let account = notification.userInfo!["account"] as? BareJID;
            let jid = notification.userInfo!["jid"] as? BareJID;
            if account != nil && jid != nil {
                let timestamp: Date? = try! self.getChatTimestampByAccountAndJidStmt.query(account!.stringValue, jid!.stringValue, 1)?["timestamp"];
                DispatchQueue.main.async() {
                    if timestamp == nil || timestamp!.timeIntervalSince1970 == 0 {
                        self.tableView.reloadData();
                    } else {
                        let pos = try! self.getChatPositionByTimestampStmt.scalar(timestamp!);
                        let indexPath = IndexPath(row: pos!, section: 0);
                        self.tableView.moveRow(at: indexPath, to: IndexPath(row: 0, section: 0));
                    }
                }
            } else {
                DispatchQueue.main.async() {
                    self.tableView.reloadData();
                }
            }
        }
        let incoming:Bool = notification.userInfo?["incoming"] as? Bool ?? false;
        if incoming {
            updateBadge();
        }
    }
    
    func chatItemsUpdated(_ notification: NSNotification) {
        updateBadge();
    }
    
    func updateBadge() {
        DispatchQueue.global(qos: .default).async {
            let unreadChats = self.xmppService.dbChatHistoryStore.countUnreadChats();
            DispatchQueue.main.async() {
                self.navigationController?.tabBarItem.badgeValue = unreadChats == 0 ? nil : String(unreadChats);
            }
        }
    }
    
    fileprivate static let todaysFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateStyle = .none;
        f.timeStyle = .short;
        return f;
        })();
    fileprivate static let defaultFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM", options: 0, locale: NSLocale.current);
//        f.timeStyle = .NoStyle;
        return f;
    })();
    fileprivate static let fullFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy", options: 0, locale: NSLocale.current);
//        f.timeStyle = .NoStyle;
        return f;
    })();
    
    fileprivate func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return ChatsListViewController.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return ChatsListViewController.fullFormatter.string(from: ts);
        } else {
            return ChatsListViewController.defaultFormatter.string(from: ts);
        }
        
    }

}

