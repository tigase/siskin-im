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
import UserNotifications
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
    
    var dataSource: ChatsDataSource!;
    
    override func viewDidLoad() {
        dataSource = ChatsDataSource(controller: self);
        super.viewDidLoad();
        
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 66.0;
        tableView.dataSource = self;
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        updateBadge();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        dataSource.reloadData();
        self.xmppService.registerEventHandler(self, for: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
        //(self.tabBarController as? CustomTabBarController)?.showTabBar();
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, for: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
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
        return dataSource.count;
        //return try! countChats.scalar() ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "ChatsListTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! ChatsListTableViewCell;
        
        let item = dataSource.item(at: indexPath);
        cell.nameLabel.text = item.name ?? item.key.jid.stringValue;
        cell.lastMessageLabel.text = item.lastMessage == nil ? nil : ((item.unread > 0 ? "" : "\u{2713}") + item.lastMessage!);
        cell.lastMessageLabel.numberOfLines = Settings.RecentsMessageLinesNo.getInt();
        
        let formattedTS = self.formatTimestamp(item.key.timestamp);
        cell.timestampLabel.text = formattedTS;

        let xmppClient = self.xmppService.getClient(forJid: item.key.account);
        switch item.key.type {
        case 1:
            let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
            cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.defaultAvatar);
            cell.avatarStatusView.setStatus(mucModule?.roomsManager.getRoom(for: item.key.jid)?.state == .joined ? Presence.Show.online : nil);
        default:
            cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.getAvatar(for: item.key.jid, account: item.key.account));
            let presenceModule: PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
            let presence = presenceModule?.presenceStore.getBestPresence(for: item.key.jid);
            cell.avatarStatusView.setStatus(presence?.show);
        }
        cell.avatarStatusView.updateCornerRadius();
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let accountCell = cell as? AccountTableViewCell {
            accountCell.avatarStatusView.updateCornerRadius();
        }
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
                let item = dataSource.itemKey(at: indexPath);
                let xmppClient = self.xmppService.getClient(forJid: item.account);
                
                var discardNotifications = false;
                switch item.type {
                case 1:
                    let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
                    if let room = mucModule?.roomsManager.getRoom(for: item.jid) {
                        mucModule?.leave(room: room);
                        discardNotifications = true;
                    }
                default:
                    let thread: String? = nil;
                    let messageModule: MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                    if let chat = messageModule?.chatManager.getChat(with: JID(item.jid), thread: thread) {
                        _ = messageModule?.chatManager.close(chat: chat);
                        discardNotifications = true;
                    }
                }
                
                if discardNotifications {
                    let accountStr = item.account.stringValue;
                    let jidStr = item.jid.stringValue;
                    UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
                        var toRemove = [String]();
                        for notification in notifications {
                            if (notification.request.content.userInfo["account"] as? String) == accountStr && (notification.request.content.userInfo["sender"] as? String) == jidStr {
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
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
        do {
            let item = dataSource.itemKey(at: indexPath);
            var identifier: String!;
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
            default:
                identifier = "ChatViewNavigationController";
            }
            
            let controller = self.storyboard?.instantiateViewController(withIdentifier: identifier);
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
        } catch _ {
        }
        
    }

    @IBAction func addMucButtonClicked(_ sender: UIBarButtonItem) {
        print("add MUC button clicked");
        let navigation = storyboard?.instantiateViewController(withIdentifier: "MucJoinNavigationController") as! UINavigationController;
        self.showDetailViewController(navigation, sender: self);
    }
    
    func handle(event: Event) {
        switch event {
        case let e as MessageModule.ChatCreatedEvent:
            // we are adding rows always on top
            DispatchQueue.main.async() {
                self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.chat.jid.bareJid, type: 0, timestamp: Date());
            }
            // if above is not working we can reload
            //tableView.reloadData();
        case let e as MessageModule.ChatClosedEvent:
            // we do not know position of chat which was closed
            //tableView.reloadData();
            DispatchQueue.main.async() {
                self.dataSource.removeChat(for: e.sessionObject.userBareJid!, with: e.chat.jid.bareJid);
            }
        case let e as PresenceModule.ContactPresenceChanged:
            //tableView.reloadData();
            guard e.sessionObject.userBareJid != nil, let from = e.presence.from else {
                // guard for possible malformed presence
                return;
            }
            DispatchQueue.main.async() {
                self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: from.bareJid);
            }
        case let e as MucModule.JoinRequestedEvent:
            DispatchQueue.main.async() {
                self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid, type: 1, timestamp: Date());
            }
        case let e as MucModule.YouJoinedEvent:
            DispatchQueue.main.async() {
                self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid);
            }
        case let e as MucModule.RoomClosedEvent:
            DispatchQueue.main.async() {
                if e.room.state == .destroyed {
                    self.dataSource.removeChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid);
                } else {
                    self.dataSource.updateChat(for: e.sessionObject.userBareJid!, with: e.room.roomJid);
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
            let jid = notification.userInfo!["sender"] as? BareJID;
            if account != nil && jid != nil {
                DispatchQueue.main.async {
                    self.dataSource.updateChat(for: account!, with: jid!, type: nil, timestamp: notification.userInfo!["timestamp"] as? Date);
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

    class ChatsViewItemKey {
        let account: BareJID;
        let jid: BareJID;
        var timestamp: Date;
        var type: Int;
        
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
            self.lastMessage = cursor["last_message"];
        }
    }
    
    class ChatsDataSource {
        
        fileprivate var getChatsList:DBStatement!;
        fileprivate var getChatDetails:DBStatement!;
        
        weak var controller: ChatsListViewController?;

        fileprivate var list: [ChatsViewItemKey] = [];
        
        var count: Int {
            return list.count;
        }
        
        init(controller: ChatsListViewController) {
            self.controller = controller;
//            self.getChats = try? controller.dbConnection.prepareStatement("SELECT id, jid, account, timestamp, thread_id, type, (SELECT data FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND item_type = 0 ORDER BY timestamp DESC LIMIT 1) AS last_message, (SELECT count(ch.id) FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND state = 2) as unread, (SELECT name FROM roster_items ri WHERE ri.account = c.account AND ri.jid = c.jid) as name FROM chats as c ORDER BY timestamp DESC");

            self.getChatsList = try? controller.dbConnection.prepareStatement("SELECT jid, account, type, timestamp FROM chats as c ORDER BY timestamp DESC");
            self.getChatDetails = try? controller.dbConnection.prepareStatement("SELECT type, (SELECT data FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND item_type = 0 ORDER BY timestamp DESC LIMIT 1) AS last_message, (SELECT count(ch.id) FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND state = 2) as unread, (SELECT name FROM roster_items ri WHERE ri.account = c.account AND ri.jid = c.jid) as name FROM chats as c WHERE c.account = :account AND c.jid = :jid");
        }
        
        func item(at position: IndexPath) -> ChatsViewItem {
            let key = list[position.row];
            let params: [String: Any?] = [ "account" : key.account, "jid" : key.jid];
            let item = ChatsViewItem(key: key);
            try! getChatDetails.query(params) { (cursor)->Void in
                item.load(from: cursor);
            }
            return item;
        }
        
        func itemKey(at position: IndexPath) -> ChatsViewItemKey {
            return list[position.row];
        }
        
        func reloadData() {
            var list: [ChatsViewItemKey] = [];
            try! getChatsList.query() { (cursor)->Void in
                let item = ChatsViewItemKey(cursor: cursor);
                list.append(item);
            }
            update(list: list);
            controller?.tableView.reloadData();
        }
        
        func updateChat(for account: BareJID, with jid: BareJID, type: Int? = nil, timestamp: Date? = nil) {
            let fromPosition = positionFor(account: account, jid: jid);
            var list = self.list;
            if fromPosition == nil {
                if type != nil && timestamp != nil {
                    let item = ChatsViewItemKey(account: account, jid: jid, type: type!, timestamp: timestamp!);
                    list.append(item);
                } else {
                    return;
                }
            } else {
                let item = self.list[fromPosition!];
                if timestamp != nil && item.timestamp.compare(timestamp!) == ComparisonResult.orderedAscending {
                    item.timestamp = timestamp!;
                }
            }
            if (timestamp != nil || SortOrder(rawValue: Settings.RecentsOrder.getString()!) == SortOrder.byAvailablityAndTime) {
                update(list: list);
                let toPosition = positionFor(account: account, jid: jid);
                notify(from: fromPosition, to: toPosition);
            } else {
                notify(from: fromPosition, to: fromPosition);
            }
        }

        func removeChat(for account: BareJID, with jid: BareJID) {
            let fromPosition = positionFor(account: account, jid: jid);
            guard fromPosition != nil else {
                return;
            }
            
            var list = self.list;
            list.remove(at: fromPosition!);
            update(list: list);
            notify(from: fromPosition, to: nil);
        }
        
        func positionFor(account: BareJID, jid: BareJID) -> Int? {
            return list.index { $0.jid == jid && $0.account == account };
        }

        fileprivate func getPresence(account: BareJID, jid: BareJID) -> Presence? {
            let presenceModule: PresenceModule? = self.controller?.xmppService.getClient(forJid: account)?.modulesManager.getModule(PresenceModule.ID);
            return presenceModule?.presenceStore.getBestPresence(for: jid);
        }
        
        func update(list: [ChatsViewItemKey]) {
            if SortOrder(rawValue: Settings.RecentsOrder.getString()!) == SortOrder.byAvailablityAndTime {
                self.list = list.sorted { (i1, i2) -> Bool in
                    let p1 = getPresence(account: i1.account, jid: i1.jid)?.show;
                    let p2 = getPresence(account: i2.account, jid: i2.jid)?.show;
                    if (p1 != nil && p2 == nil) {
                        return true;
                    } else if (p1 == nil && p2 != nil) {
                        return false;
                    }
                    
                    return i1.timestamp.compare(i2.timestamp) == .orderedDescending
                };
            } else {
                self.list = list.sorted { (i1, i2) -> Bool in
                    i1.timestamp.compare(i2.timestamp) == .orderedDescending
                };
            }
        }
        
        func notify(from: Int?, to: Int?) {
            guard from != nil || to != nil else {
                return;
            }
            notify(from: from != nil ? IndexPath(row: from!, section: 0) : nil, to: to != nil ? IndexPath(row: to!, section: 0) : nil);
        }
        
        func notify(from: IndexPath?, to: IndexPath?) {
            if from != nil && to != nil {
                if from != to {
                    controller?.tableView.moveRow(at: from!, to: to!);
                }
                controller?.tableView.reloadRows(at: [to!], with: .fade);
            } else if to == nil {
                controller?.tableView.deleteRows(at: [from!], with: .fade);
            } else {
                controller?.tableView.insertRows(at: [to!], with: .fade);
            }
        }
    }
    
    public enum SortOrder: String {
        case byTime
        case byAvailablityAndTime
    }
}

