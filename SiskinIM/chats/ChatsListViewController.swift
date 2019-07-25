//
// ChatListViewController.swift
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
import UserNotifications
import TigaseSwift

class ChatsListViewController: CustomTableViewController, EventHandler {
    var dbConnection:DBConnection!;
    var xmppService:XmppService!;
    
    @IBOutlet var addMucButton: UIBarButtonItem!
    
    var dataSource: ChatsDataSource!;
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        dbConnection = (UIApplication.shared.delegate as! AppDelegate).dbConnection;
        dataSource = ChatsDataSource(controller: self);
        super.viewDidLoad();
        
        tableView.rowHeight = UITableView.automaticDimension;
        tableView.estimatedRowHeight = 66.0;
        tableView.dataSource = self;
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        updateBadge();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        dataSource.reloadData();
        self.xmppService.registerEventHandler(self, for: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
        //(self.tabBarController as? CustomTabBarController)?.showTabBar();
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        self.navigationController?.navigationBar.backgroundColor = Appearance.current.controlBackgroundColor();
        super.viewWillAppear(animated);
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, for: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
        NotificationCenter.default.removeObserver(self, name: AvatarManager.AVATAR_CHANGED, object: nil);
        dataSource.cache.removeAllObjects();
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
        return dataSource.count;
        //return try! countChats.scalar() ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = Settings.EnableNewUI.getBool() ? "ChatsListTableViewCellNew" : "ChatsListTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! ChatsListTableViewCell;
        
        if let item = dataSource.item(at: indexPath) {
            cell.nameLabel.textColor = Appearance.current.textColor();
            cell.nameLabel.text = item.name ?? item.key.jid.stringValue;
            cell.nameLabel.font = item.unread > 0 ? UIFont.boldSystemFont(ofSize: cell.nameLabel.font.pointSize) : UIFont.systemFont(ofSize: cell.nameLabel.font.pointSize);
            if Settings.EnableNewUI.getBool() {
                cell.lastMessageLabel.textColor = Appearance.current.textColor();
            } else {
                cell.lastMessageLabel.textColor = Appearance.current.secondaryTextColor();
            }
            if item.lastMessage != nil && Settings.EnableMarkdownFormatting.getBool() {
                let msg = NSMutableAttributedString(string: item.lastMessage!);
                Markdown.applyStyling(attributedString: msg, font: cell.lastMessageLabel.font, showEmoticons: Settings.ShowEmoticons.getBool())
                let text = NSMutableAttributedString(string: item.unread > 0 ? "" : "\u{2713}");
                text.append(msg);
                cell.lastMessageLabel.attributedText = text;
            } else {
                cell.lastMessageLabel.text = item.lastMessage == nil ? nil : ((item.unread > 0 ? "" : "\u{2713}") + item.lastMessage!);
            }
            cell.lastMessageLabel.numberOfLines = Settings.RecentsMessageLinesNo.getInt();
            //        cell.lastMessageLabel.font = item.unread > 0 ? UIFont.boldSystemFont(ofSize: cell.lastMessageLabel.font.pointSize) : UIFont.systemFont(ofSize: cell.lastMessageLabel.font.pointSize);
            
            
            let formattedTS = self.formatTimestamp(item.key.timestamp);
            cell.timestampLabel.text = formattedTS;
            cell.timestampLabel.textColor = Appearance.current.secondaryTextColor();
            
            let xmppClient = self.xmppService.getClient(forJid: item.key.account);
            switch item.key.type {
            case 1:
                let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
                cell.avatarStatusView.updateAvatar(manager: self.xmppService.avatarManager, for: item.key.account, with: item.key.jid, name: nil, orDefault: self.xmppService.avatarManager.defaultGroupchatAvatar);
                cell.avatarStatusView.setStatus(mucModule?.roomsManager.getRoom(for: item.key.jid)?.state == .joined ? Presence.Show.online : nil);
            default:
                cell.avatarStatusView.updateAvatar(manager: self.xmppService.avatarManager, for: item.key.account, with: item.key.jid, name: item.name, orDefault: self.xmppService.avatarManager.defaultAvatar);
                let presenceModule: PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                let presence = presenceModule?.presenceStore.getBestPresence(for: item.key.jid);
                cell.avatarStatusView.setStatus(presence?.show);
            }
        }
        cell.avatarStatusView.updateCornerRadius();
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = Appearance.current.tableViewCellBackgroundColor();
        if let accountCell = cell as? ChatsListTableViewCell {
            accountCell.avatarStatusView.updateCornerRadius();
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if (indexPath.section == 0) {
            return true;
        }
        return false;
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            if indexPath.section == 0 {
                let item = dataSource.itemKey(at: indexPath);
                let xmppClient = self.xmppService.getClient(forJid: item.account);
                
                var discardNotifications = false;
                switch item.type {
                case 1:
                    let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
                    if let room = mucModule?.roomsManager.getRoom(for: item.jid) {
                        if room.presences[room.nickname]?.affiliation == .owner {
                            let alert = UIAlertController(title: "Delete group chat?", message: "You are leaving the group chat \((room as? DBRoom)?.roomName ?? room.roomJid.stringValue)", preferredStyle: .actionSheet);
                            alert.addAction(UIAlertAction(title: "Leave chat", style: .default, handler: { (action) in
                                PEPBookmarksModule.remove(xmppService: self.xmppService, from: item.account, bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: room.jid, autojoin: false));
                                mucModule?.leave(room: room);
                                self.discardNotifications(for: item);

                            }))
                            alert.addAction(UIAlertAction(title: "Delete chat", style: .destructive, handler: { (action) in
                                PEPBookmarksModule.remove(xmppService: self.xmppService, from: item.account, bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: room.jid, autojoin: false));
                                mucModule?.destroy(room: room);
                                self.discardNotifications(for: item);
                                
                            }));
                            alert.popoverPresentationController?.sourceView = self.view;
                            alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);
                            self.present(alert, animated: true, completion: nil);
                        } else {
                            PEPBookmarksModule.remove(xmppService: xmppService, from: item.account, bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: room.jid, autojoin: false));
                            mucModule?.leave(room: room);
                            discardNotifications = true;
                        }
                    } else {
                        if let chatId = xmppService.dbChatStore.getId(for: item.account, with: item.jid) {
                            DispatchQueue.global().async {
                                if self.xmppService.dbChatStore.close(withId: chatId) {
                                    DispatchQueue.main.async() {
                                        self.dataSource.removeChat(for: item.account, with: item.jid);
                                    }
                                }
                            }
                            discardNotifications = true;
                        }
                    }
                default:
                    let thread: String? = nil;
                    let messageModule: MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                    if let chat = messageModule?.chatManager.getChat(with: JID(item.jid), thread: thread) {
                        _ = messageModule?.chatManager.close(chat: chat);
                        discardNotifications = true;
                    } else {
                        if let chatId = xmppService.dbChatStore.getId(for: item.account, with: item.jid) {
                            DispatchQueue.global().async {
                                if self.xmppService.dbChatStore.close(withId: chatId) {
                                    DispatchQueue.main.async() {
                                        self.dataSource.removeChat(for: item.account, with: item.jid);
                                    }
                                }
                            }
                            discardNotifications = true;
                        }
                    }
                }
                
                if discardNotifications {
                    self.discardNotifications(for: item);
                }
            }
        }
    }
    
    func discardNotifications(for item: ChatsViewItemKey) {
        let accountStr = item.account.stringValue.lowercased();
        let jidStr = item.jid.stringValue.lowercased();
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            var toRemove = [String]();
            for notification in notifications {
                if (notification.request.content.userInfo["account"] as? String)?.lowercased() == accountStr && (notification.request.content.userInfo["sender"] as? String)?.lowercased() == jidStr {
                    toRemove.append(notification.request.identifier);
                }
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
            
            if Settings.DeleteChatHistoryOnChatClose.getBool() {
                self.xmppService.dbChatHistoryStore.deleteMessages(for: item.account, with: item.jid);
            } else {
                self.xmppService.dbChatHistoryStore.markAsRead(for: item.account, with: item.jid);
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
        let item = dataSource.itemKey(at: indexPath);
        var identifier: String!;
        var controller: UIViewController? = nil;
        switch item.type {
        case 1:
            identifier = "RoomViewNavigationController";
            let client = self.xmppService.getClient(forJid: item.account);
            let mucModule: MucModule? = client?.modulesManager?.getModule(MucModule.ID);
            let room = mucModule?.roomsManager.getRoom(for: item.jid);
            guard room != nil else {
                if client == nil {
                    let alert = UIAlertController.init(title: "Warning", message: "Account is disabled.\nDo you want to enable account?", preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                    alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                        if let accountInstance = AccountManager.getAccount(forJid: item.account.stringValue) {
                            accountInstance.active = true;
                            AccountManager.updateAccount(accountInstance);
                        }
                    }));
                    self.present(alert, animated: true, completion: nil);
                }
                return;
            }
            controller = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: identifier);
        default:
            identifier = "ChatViewNavigationController";
            controller = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: identifier);
        }
        
        let navigationController = controller as? UINavigationController;
        let destination = navigationController?.visibleViewController ?? controller;
            
        if let baseChatViewController = destination as? BaseChatViewController {
            baseChatViewController.account = item.account;
            baseChatViewController.jid = JID(item.jid);
        }
        destination?.hidesBottomBarWhenPushed = true;
                
        if controller != nil {
            self.showDetailViewController(controller!, sender: self);
        }
    }

    @IBAction func addMucButtonClicked(_ sender: UIBarButtonItem) {
        print("add MUC button clicked");
        
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
        controller.popoverPresentationController?.barButtonItem = sender;
        
        controller.addAction(UIAlertAction(title: "New private group chat", style: .default, handler: { action in
            let newGroupchat = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "MucNewGroupchatController") as! MucNewGroupchatController;
            newGroupchat.groupchatType = .privateGroupchat;
            newGroupchat.xmppService = self.xmppService;
            newGroupchat.hidesBottomBarWhenPushed = true;
//            self.showDetailViewController(newGroupchat, sender: self);
            let navController = UINavigationController(rootViewController: newGroupchat);
            navController.modalPresentationStyle = .formSheet;
            self.present(navController, animated: true, completion: nil);
        }));
        controller.addAction(UIAlertAction(title: "New public group chat", style: .default, handler: { action in
            let newGroupchat = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "MucNewGroupchatController") as! MucNewGroupchatController;
            newGroupchat.groupchatType = .publicGroupchat;
            newGroupchat.xmppService = self.xmppService;
            newGroupchat.hidesBottomBarWhenPushed = true;
            let navController = UINavigationController(rootViewController: newGroupchat);
            navController.modalPresentationStyle = .formSheet;
            self.present(navController, animated: true, completion: nil);
        }));
        
        controller.addAction(UIAlertAction(title: "Join group chat", style: .default, handler: { action in
            let navigation = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "MucJoinNavigationController") as! UINavigationController;
            navigation.modalPresentationStyle = .formSheet;
            navigation.visibleViewController?.hidesBottomBarWhenPushed = true;
//            self.showDetailViewController(navigation, sender: self);
            self.present(navigation, animated: true, completion: nil);
        }));
        
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
        
        self.present(controller, animated: true, completion: nil);
    }
    
    func handle(event: Event) {
        switch event {
        case let e as MessageModule.ChatCreatedEvent:
            // we are adding rows always on top
            self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.chat.jid.bareJid, type: 0, timestamp: Date(), onUpdate: nil);
            // if above is not working we can reload
        case let e as MessageModule.ChatClosedEvent:
            // we do not know position of chat which was closed
            //tableView.reloadData();
            self.dataSource.removeChat(for: e.sessionObject.userBareJid!, with: e.chat.jid.bareJid);
            self.closeBaseChatView(for: e.sessionObject.userBareJid!, jid: e.chat.jid);
        case let e as PresenceModule.ContactPresenceChanged:
            //tableView.reloadData();
            guard e.sessionObject.userBareJid != nil, let from = e.presence.from else {
                // guard for possible malformed presence
                return;
            }
            self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: from.bareJid, onUpdate: nil);
        case let e as MucModule.JoinRequestedEvent:
            self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid, type: 1, timestamp: Date(), onUpdate: nil);
        case let e as MucModule.YouJoinedEvent:
            self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid, onUpdate: nil);
        case let e as MucModule.RoomClosedEvent:
            if e.room.state == .destroyed {
                self.dataSource.removeChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid);
                self.closeBaseChatView(for: e.sessionObject.userBareJid!, jid: e.room.jid);
            } else {
                self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid, onUpdate: nil);
            }
        case let e as RosterModule.ItemUpdatedEvent:
            guard let account = e.sessionObject.userBareJid, let jid = e.rosterItem?.jid else {
                return;
            }
            self.dataSource.updateChat(for: account, with: jid.bareJid, onUpdate: { item in
                item.name = e.rosterItem?.name;
                return true;
            });
        default:
            break;
        }
    }
    
    fileprivate func closeBaseChatView(for account: BareJID, jid: JID) {
        DispatchQueue.main.async {
            if let navController = self.splitViewController?.viewControllers.first(where: { c -> Bool in
                return c is UINavigationController;
            }) as? UINavigationController, let controller = navController.visibleViewController as? BaseChatViewController {
                if controller.account == account && controller.jid == jid {
                    self.showDetailViewController(self.storyboard!.instantiateViewController(withIdentifier: "emptyDetailViewController"), sender: self);
                }
            }
        }
    }
    
    @objc func avatarChanged(_ notification: NSNotification) {
        if let _ = notification.userInfo!["jid"] as? BareJID {
            DispatchQueue.main.async {
                self.tableView.reloadData();
            }
        }
    }
    
    @objc func newMessage(_ notification:NSNotification) {
        let state = notification.userInfo!["state"] as! DBChatHistoryStore.State;
        if navigationController?.visibleViewController == self {
//            tableView.reloadData();
            let account = notification.userInfo!["account"] as? BareJID;
            let jid = notification.userInfo!["sender"] as? BareJID;
            let ts = notification.userInfo!["timestamp"] as? Date;
            let encryption = notification.userInfo!["encryption"] as! MessageEncryption;
            if account != nil && jid != nil {
                //DispatchQueue.main.async {
                    self.dataSource.updateChat(for: account!, with: jid!, type: nil, timestamp: ts, onUpdate: { item in
                        if (ts != nil && item.key.timestamp.compare(ts!) == ComparisonResult.orderedSame) || item.lastMessage == nil {
                            item.lastMessage = encryption.message() ?? (notification.userInfo!["body"] as? String);
                            switch state {
                                case .incoming_unread, .incoming_error_unread:
                                    item.unread += 1;
                                default:
                                    break;
                            }
                            return true;
                        }
                        return false;
                    });
                //}
            }
        }
        switch state {
            case .incoming_unread, .incoming_error_unread:
                updateBadge();
            default:
                break;
        }
    }
    
    @objc func chatItemsUpdated(_ notification: NSNotification) {
        let action: String = notification.userInfo!["action"] as! String;
        let account: BareJID = notification.userInfo!["account"] as! BareJID;
        let jid: BareJID = notification.userInfo!["jid"] as! BareJID;
        if action == "markedRead" {
            DispatchQueue.main.async {
                self.dataSource.updateChat(for: account, with: jid, onUpdate: { item in
                    if item.unread != 0 {
                        item.unread = 0;
                        return true;
                    }
                    return false;
                });
            }
        }
        if action == "roomNameChanged" {
            DispatchQueue.main.async {
                self.dataSource.updateChat(for: account, with: jid, onUpdate: { item in
                    let newName = notification.userInfo!["roomName"] as? String;
                    if item.name != newName {
                        item.name = newName;
                        return true;
                    }
                    return false;
                });
            }
        }
        updateBadge();
    }
    
    func updateBadge() {
        self.xmppService.dbChatHistoryStore.countUnreadChats() { unreadChats in
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

    class ChatsViewItemKey: NSObject {
        let account: BareJID;
        let jid: BareJID;
        var timestamp: Date;
        var type: Int;
        var show: Presence.Show?;

        override var description: String {
            return "account: \(account), jid: \(jid), ts: \(timestamp)"
        }
        
        init(cursor: DBCursor) {
            self.account = cursor["account"]!;
            self.jid = cursor["jid"]!;
            self.timestamp = cursor["timestamp"]!;
            self.type = cursor["type"]!;
        }
        
        init(account: BareJID, jid: BareJID, type: Int, timestamp: Date) {
            self.account = account;
            self.jid = jid;
            self.timestamp = timestamp;
            self.type = type;
        }
        
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ChatsViewItemKey else {
                return false;
            }
            
            return self.account == other.account && self.jid == other.jid;
        }
        
        override var hash: Int {
            return self.account.hashValue ^ self.jid.hashValue;
        }
    }
    
    class ChatsViewItem {
        let key: ChatsViewItemKey;
        var name: String?;
        var unread: Int = 0;
        var lastMessage: String?;
        
        init(key: ChatsViewItemKey) {
            self.key = key;
        }
        
        func load(from cursor: DBCursor) {
            self.name = cursor["name"];
            self.unread = cursor["unread"]!;
            let encryption = MessageEncryption(rawValue: cursor["last_encryption"] ?? 0) ?? .none;
            self.lastMessage = encryption.message() ?? cursor["last_message"];
        }
    }
    
    class ChatsDataSource {
        
        fileprivate var getChatsList:DBStatement!;
        fileprivate var getChatDetails:DBStatement!;
        
        weak var controller: ChatsListViewController?;

        fileprivate var list: [ChatsViewItemKey] = []
//        {
//            willSet {
//                // list will change, so we should execute any delayed refresh requests
//                executeDelayedReloadRow();
//            }
//        }
        fileprivate var cache = NSCache<ChatsViewItemKey,ChatsViewItem>();
        fileprivate var queue = DispatchQueue(label: "chats_data_source", qos: .background);
        
        var count: Int {
            return list.count;
        }
        
        init(controller: ChatsListViewController) {
            self.controller = controller;
//            self.getChats = try? controller.dbConnection.prepareStatement("SELECT id, jid, account, timestamp, thread_id, type, (SELECT data FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND item_type = 0 ORDER BY timestamp DESC LIMIT 1) AS last_message, (SELECT count(ch.id) FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND state = 2) as unread, (SELECT name FROM roster_items ri WHERE ri.account = c.account AND ri.jid = c.jid) as name FROM chats as c ORDER BY timestamp DESC");
            self.getChatsList = try? controller.dbConnection.prepareStatement("SELECT jid, account, type, timestamp FROM chats as c ORDER BY timestamp DESC");
            self.getChatDetails = try? controller.dbConnection.prepareStatement("SELECT type, last.data AS last_message, last.encryption AS last_encryption, (SELECT count(ch.id) FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND state in (\(DBChatHistoryStore.State.incoming_unread.rawValue), \(DBChatHistoryStore.State.incoming_error_unread.rawValue), \(DBChatHistoryStore.State.outgoing_error_unread.rawValue))) as unread, IFNULL(c.name, (SELECT name FROM roster_items ri WHERE ri.account = c.account AND ri.jid = c.jid)) as name FROM chats as c LEFT JOIN (SELECT data, encryption FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid AND item_type = 0 ORDER BY timestamp DESC LIMIT 1) last WHERE c.account = :account AND c.jid = :jid");
        }
        
        func item(at position: IndexPath) -> ChatsViewItem? {
            let key = list[position.row];
            if let item = cache.object(forKey: key) {
                return item;
            }
            
            let params: [String: Any?] = [ "account" : key.account, "jid" : key.jid];
            let item: ChatsViewItem? = try! getChatDetails.findFirst(params) { (cursor) in
                let tmp = ChatsViewItem(key: key);
                tmp.load(from: cursor);
                return tmp;
            };
            if item != nil {
                cache.setObject(item!, forKey: key);
            }
            return item;
        }
        
        func itemKey(at position: IndexPath) -> ChatsViewItemKey {
            return list[position.row];
        }
        
        func reloadData() {
//            delayedReloadIndexPath = nil;
            queue.async {
                var list: [ChatsViewItemKey] = try! self.getChatsList.query() { (cursor) in ChatsViewItemKey(cursor: cursor) }
                list.forEach({ (item) in
                    item.show = self.getPresence(account: item.account, jid: item.jid)?.show;
                })
                DispatchQueue.main.sync {
                    self.list = self.sort(list: &list);
                    self.cache.removeAllObjects();
                    self.controller?.tableView.reloadData();
                }
            }
        }
        
        func updateChat(for account: BareJID, with jid: BareJID, type: Int? = nil, timestamp: Date? = nil, onUpdate: ((ChatsViewItem)->Bool)?) {
            queue.async {
                var list = DispatchQueue.main.sync { return self.list; };
                let fromPosition = ChatsDataSource.position(in: &list, account: account, jid: jid);
                var needRefresh = true;
                if fromPosition == nil {
                    if type != nil && timestamp != nil {
                        let item = ChatsViewItemKey(account: account, jid: jid, type: type!, timestamp: timestamp!);
                        item.show = self.getPresence(account: account, jid: jid)?.show;
                        list.append(item);
                    } else {
                        return;
                    }
                } else {
                    let item = list[fromPosition!];
                    item.show = self.getPresence(account: account, jid: jid)?.show;
                    let viewItem = self.cache.object(forKey: item);
                    if timestamp != nil && ((item.timestamp.compare(timestamp!) == ComparisonResult.orderedAscending) || (viewItem != nil && viewItem!.lastMessage == nil)) {
                        item.timestamp = timestamp!;
                    }
                    if viewItem != nil {
                        needRefresh = onUpdate?(viewItem!) ?? true;
                    } else {
                        needRefresh = false;
                    }
                }
                if (timestamp != nil || SortOrder(rawValue: Settings.RecentsOrder.getString()!) == SortOrder.byAvailablityAndTime) {
                    list = self.sort(list: &list);
                    let toPosition = ChatsDataSource.position(in: &list, account: account, jid: jid);
                    DispatchQueue.main.async {
                        self.list = list;
                        self.notify(from: fromPosition, to: toPosition, needRefresh: needRefresh);
                    }
                } else {
                    DispatchQueue.main.async {
                        self.notify(from: fromPosition, to: fromPosition);
                    }
                }
            }
        }

        func removeChat(for account: BareJID, with jid: BareJID) {
            queue.async {
                var list = DispatchQueue.main.sync { return self.list; }
                let fromPosition = ChatsDataSource.position(in: &list, account: account, jid: jid);
                guard fromPosition != nil else {
                    return;
                }
            
                let key = list.remove(at: fromPosition!);
                DispatchQueue.main.async {
                    self.list = list;
                    self.cache.removeObject(forKey: key);
                    self.notify(from: fromPosition, to: nil);
                }
            }
        }
        
        fileprivate static func position(in list: inout [ChatsViewItemKey], account: BareJID, jid: BareJID) -> Int? {
            return list.firstIndex { $0.jid == jid && $0.account == account };
        }
        
        fileprivate func getPresence(account: BareJID, jid: BareJID) -> Presence? {
            let presenceModule: PresenceModule? = self.controller?.xmppService.getClient(forJid: account)?.modulesManager.getModule(PresenceModule.ID);
            return presenceModule?.presenceStore.getBestPresence(for: jid);
        }
        
        fileprivate func sort(list: inout [ChatsViewItemKey]) -> [ChatsViewItemKey] {
            if SortOrder(rawValue: Settings.RecentsOrder.getString()!) == SortOrder.byAvailablityAndTime {
                return list.sorted { (i1, i2) -> Bool in
                    let p1 = i1.show;
                    let p2 = i2.show;
                    if (p1 != nil && p2 == nil) {
                        return true;
                    } else if (p1 == nil && p2 != nil) {
                        return false;
                    }
                    
                    return i1.timestamp.compare(i2.timestamp) == .orderedDescending
                };
            } else {
                return list.sorted { (i1, i2) -> Bool in
                    i1.timestamp.compare(i2.timestamp) == .orderedDescending
                };
            }
        }
        
        func notify(from: Int?, to: Int?, needRefresh: Bool = true) {
            guard from != nil || to != nil else {
                return;
            }
            notify(from: from != nil ? IndexPath(row: from!, section: 0) : nil, to: to != nil ? IndexPath(row: to!, section: 0) : nil, needRefresh: needRefresh);
        }
        
        func notify(from: IndexPath?, to: IndexPath?, needRefresh: Bool = true) {
            if from != nil && to != nil {
                if from != to {
                    controller?.tableView.moveRow(at: from!, to: to!);
                }
                if needRefresh {
                    controller?.tableView.reloadRows(at: [to!], with: .none);
                }
            } else if to == nil {
                controller?.tableView.deleteRows(at: [from!], with: .fade);
            } else {
                controller?.tableView.insertRows(at: [to!], with: .fade);
            }
        }
        
//        fileprivate var delayedReloadIndexPath: IndexPath? = nil;
//
//        func calculateDelayedReloadRow(offset: Int) {
//            delayedReloadIndexPath = IndexPath(row: delayedReloadIndexPath!.row + offset, section: 0);
//        }

//        func delayedReloadRows(at indexPath: IndexPath) {
//            if delayedReloadIndexPath != nil && delayedReloadIndexPath! == indexPath {
//                return;
//            }
//            executeDelayedReloadRow();
//            delayedReloadIndexPath = indexPath;
//
//            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
//                self.executeDelayedReloadRow();
//            }
//        }
//
//        func executeDelayedReloadRow() {
//            guard delayedReloadIndexPath != nil else {
//                return;
//            }
//
//            controller?.tableView.reloadRows(at: [delayedReloadIndexPath!], with: .fade);
//            delayedReloadIndexPath = nil;
//        }
    }
    
    public enum SortOrder: String {
        case byTime
        case byAvailablityAndTime
    }
}

