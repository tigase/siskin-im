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

class ChatsListViewController: CustomTableViewController {
    var xmppService:XmppService!;
    
    @IBOutlet var addMucButton: UIBarButtonItem!
    
    var dataSource: ChatsDataSource?;
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        dataSource = ChatsDataSource(controller: self);
        super.viewDidLoad();
        
        tableView.rowHeight = UITableView.automaticDimension;
        tableView.estimatedRowHeight = 66.0;
        tableView.dataSource = self;
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.unreadCountChanged), name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: nil);
//        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil);
        self.updateBadge();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.navigationBar.backgroundColor = Appearance.current.controlBackgroundColor;
//        if dataSource == nil {
//            dataSource = ChatsDataSource(controller: self);
//        }
        super.viewWillAppear(animated);
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
    }

    deinit {
        NotificationCenter.default.removeObserver(self);
    }
    
//    @objc func appMovedToBackground(_ notification: Notification) {
//        DispatchQueue.main.async {
//            self.dataSource = nil;
//        }
//    }
//    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource?.count ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "ChatsListTableViewCellNew";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! ChatsListTableViewCell;
        
        if let item = dataSource!.item(at: indexPath) {
            cell.nameLabel.textColor = Appearance.current.labelColor;
            cell.nameLabel.font = item.unread > 0 ? UIFont.boldSystemFont(ofSize: cell.nameLabel.font.pointSize) : UIFont.systemFont(ofSize: cell.nameLabel.font.pointSize);
            cell.lastMessageLabel.textColor = Appearance.current.secondaryLabelColor;
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
            
            
            let formattedTS = self.formatTimestamp(item.timestamp);
            cell.timestampLabel.text = formattedTS;
            cell.timestampLabel.textColor = Appearance.current.secondaryLabelColor;
            
            let xmppClient = self.xmppService.getClient(forJid: item.account);
            switch item {
            case let room as DBRoom:
                cell.avatarStatusView.set(name: nil, avatar: AvatarManager.instance.avatar(for: room.roomJid, on: room.account), orDefault: AvatarManager.instance.defaultGroupchatAvatar);
                cell.avatarStatusView.setStatus(room.state == .joined ? Presence.Show.online : nil);
                cell.nameLabel.text = room.name ?? item.jid.stringValue;
            default:
                let rosterModule: RosterModule? = xmppClient?.modulesManager.getModule(RosterModule.ID);
                let rosterItem = rosterModule?.rosterStore.get(for: item.jid);
                let name = rosterItem?.name ?? item.jid.bareJid.stringValue;
                cell.nameLabel.text = name;
                cell.avatarStatusView.set(name: name, avatar: AvatarManager.instance.avatar(for: item.jid.bareJid, on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
                let presenceModule: PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                let presence = presenceModule?.presenceStore.getBestPresence(for: item.jid.bareJid);
                cell.avatarStatusView.setStatus(presence?.show);
            }
        }
        cell.avatarStatusView.updateCornerRadius();
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = Appearance.current.systemBackground;
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
                guard let item = dataSource!.item(at: indexPath) else {
                    return;
                }
                
                let xmppClient = self.xmppService.getClient(forJid: item.account);
                
                var discardNotifications = false;
                switch item {
                case let room as DBRoom:
                    let mucModule: MucModule? = xmppClient?.modulesManager.getModule(MucModule.ID);
                    
                    if room.presences[room.nickname]?.affiliation == .owner {
                        let alert = UIAlertController(title: "Delete group chat?", message: "You are leaving the group chat \((room as? DBRoom)?.name ?? room.roomJid.stringValue)", preferredStyle: .actionSheet);
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

                        room.checkTigasePushNotificationRegistrationStatus { (result) in
                            switch result {
                            case .failure(_):
                                break;
                            case .success(let value):
                                guard value else {
                                    return;
                                }
                                room.registerForTigasePushNotification(false, completionHandler: { (regResult) in
                                    DispatchQueue.main.async {
                                        let alert = UIAlertController(title: "Push notifications", message: "You've left there room \((room as? DBRoom)?.name ?? room.roomJid.stringValue) and push notifications for this room were disabled!\nYou may need to reenable them on other devices.", preferredStyle: .actionSheet);
                                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                                        alert.popoverPresentationController?.sourceView = self.view;
                                        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);
                                        self.present(alert, animated: true, completion: nil);
                                    }
                                })
                            }
                        }

                        discardNotifications = true;
                    }
                case let chat as DBChat:
                    let thread: String? = nil;
                    let messageModule: MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                    _ = messageModule?.chatManager.close(chat: chat);
                    discardNotifications = true;
                default:
                    break;
                }
                
                if discardNotifications {
                    self.discardNotifications(for: item);
                }
            }
        }
    }
    
    func discardNotifications(for item: DBChatProtocol) {
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
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
        guard let item = dataSource!.item(at: indexPath) else {
            return;
        }
        var identifier: String!;
        var controller: UIViewController? = nil;
        switch item {
        case let room as DBRoom:
            identifier = "RoomViewNavigationController";
            controller = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: identifier);
        default:
            identifier = "ChatViewNavigationController";
            controller = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: identifier);
        }
        
        let navigationController = controller as? UINavigationController;
        let destination = navigationController?.visibleViewController ?? controller;
            
        if let baseChatViewController = destination as? BaseChatViewController {
            baseChatViewController.account = item.account;
            baseChatViewController.jid = item.jid.bareJid;
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
//            navigation.visibleViewController?.hidesBottomBarWhenPushed = true;
//            self.showDetailViewController(navigation, sender: self);
            self.present(navigation, animated: true, completion: nil);
        }));
        
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
        
        self.present(controller, animated: true, completion: nil);
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection);
//        if #available(iOS 13.0, *) {
//            let changed = previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false;
//            
//            let subtype: Appearance.SubColorType = traitCollection.userInterfaceStyle == .dark ? .dark : .light;
//            let colorType = Appearance.current.colorType;
//            Appearance.current = Appearance.values.first(where: { (item) -> Bool in
//                return item.colorType == colorType && item.subtype == subtype;
//            })
//        }
    }
    
    fileprivate func closeBaseChatView(for account: BareJID, jid: BareJID) {
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
    
    @objc func unreadCountChanged(_ notification: Notification) {
        updateBadge();
    }
    
    func updateBadge() {
        let unreadChats = DBChatStore.instance.unreadChats;
        DispatchQueue.main.async {
            self.navigationController?.tabBarItem.badgeValue = unreadChats == 0 ? nil : String(unreadChats);
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
    
    class ChatsDataSource {
        
        weak var controller: ChatsListViewController?;

        fileprivate var dispatcher = DispatchQueue(label: "chats_data_source", qos: .background);
                
        var count: Int {
            self.store.count;
        }
        
        init(controller: ChatsListViewController) {
            self.controller = controller;
            
            NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(chatOpened), name: DBChatStore.CHAT_OPENED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(chatClosed), name: DBChatStore.CHAT_CLOSED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(chatUpdated), name: DBChatStore.CHAT_UPDATED, object: nil);
            
            applyActionsQueue.async {
                DispatchQueue.main.sync {
                    self.store = ChatsStore(items: DBChatStore.instance.getChats().sorted(by: ChatsDataSource.chatsSorter));
                    self.controller?.tableView.reloadData();
                }
            }
        }
        
        func item(at indexPath: IndexPath) -> DBChatProtocol? {
            return self.store.item(at: indexPath.row);
        }
        
        func getChat(at index: Int) -> DBChatProtocol? {
            return self.store.item(at: index);
        }

        static func chatsSorter(i1: DBChatProtocol, i2: DBChatProtocol) -> Bool {
            return i1.timestamp.compare(i2.timestamp) == .orderedDescending;
        }
        
        @objc func avatarChanged(_ notification: Notification) {
            guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
                return;
            }
            self.refreshItem(for: account, with: jid);
        }
        
        @objc func chatOpened(_ notification: Notification) {
            guard let opened = notification.object as? DBChatProtocol else {
                return;
            }
            
            addItem(chat: opened);
        }
        
        @objc func chatClosed(_ notification: Notification) {
            guard let opened = notification.object as? DBChatProtocol else {
                return;
            }
            
            self.removeItem(for: opened.account, jid: opened.jid.bareJid);
        }
        
        @objc func chatUpdated(_ notification: Notification) {
            guard let e = notification.object as? DBChatProtocol else {
                return;
            }
            
            self.refreshItem(for: e.account, with: e.jid.bareJid);
        }
        
        @objc func contactPresenceChanged(_ notification: Notification) {
            guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
                return;
            }
            
            guard let account = e.sessionObject.userBareJid, let jid = e.presence.from?.bareJid else {
                return;
            }
            
            self.refreshItem(for: account, with: jid);
        }

        @objc func rosterItemUpdated(_ notification: Notification) {
            guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
                return;
            }
            
            guard let account = e.sessionObject.userBareJid, let rosterItem = e.rosterItem else {
                return;
            }
            self.refreshItem(for: account, with: rosterItem.jid.bareJid);
        }
        
        private var store: ChatsStore = ChatsStore();
        private var actionQueue: [ChatsStoreQueueItem] = [];
        private var actionSemaphore = DispatchSemaphore(value: 1);
        private let applyActionsQueue = QueueDispatcher(label: "applyActionsQueue");
        
        private func applyActions() {
            actionSemaphore.wait();
            let actions = dispatcher.sync { () -> [ChatsStoreQueueItem] in
                let tmp = self.actionQueue;
                self.actionQueue = [];
                return tmp;
            }
            
            print("XX: executing for", actions.count, "actions");
            
            var store = DispatchQueue.main.sync { return self.store };
            
//            let removeIndexes = store.indexes(for: actions.filter { (item) -> Bool in
//                item.action == .remove;
//            });
//            let refreshActions = actions.filter { (item) -> Bool in
//                item.action == .refresh;
//            };
//            let refreshIndexes = store.indexes(for: refreshActions);
//
//            store.remove(for: removeIndexes);
//
//            let addActions = actions.filter { (item) -> Bool in
//                return item.action == .add;
//            }
//
//            addActions.forEach { (item) in
//                _ = store.add(for: item)
//            }
//
//            let addIndexes = store.indexes(for: addActions + refreshActions);

            let removeIndexes = store.indexes(for: actions);
            
            let addDBChatItems = actions.filter({ item -> Bool in return item.action != .remove && item is DBChatQueueItem }).map({ (item) -> DBChatQueueItem in
                return item as! DBChatQueueItem;
            });
            
            let addAccountJidItems = actions.filter({ item -> Bool in return item.action != .remove && item is AccountJidQueueItem });
            let addMappedAccountJidItems = store.indexes(for: addAccountJidItems).map(({ DBChatQueueItem(action: .add, chat: store.item(at: $0)!) }));

            store.remove(for: removeIndexes);
            
            let addActions = (addDBChatItems + addMappedAccountJidItems).filter({ item -> Bool in return store.add(for: item); });
            let addIndexes = store.indexes(for: addActions);
            
            DispatchQueue.main.async {
                self.store = store;
                if let tableView = self.controller?.tableView {
                    tableView.performBatchUpdates({
//                        tableView.deleteRows(at: (removeIndexes + refreshIndexes).map{ IndexPath(row: $0, section: 0)}, with: .fade);
                        print("removing rows:", removeIndexes);
                        tableView.deleteRows(at: removeIndexes.map{ IndexPath(row: $0, section: 0)}, with: .fade);
                        print("adding rows:", addIndexes);
                        tableView.insertRows(at: addIndexes.map { IndexPath(row: $0, section: 0)}, with: .fade);
                    }, completion: { (result) in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                            self.actionSemaphore.signal();
                        }
                    })
                } else {
                    print("failed to access table view");
                }
            }
        }
        
        func refreshItem(for account: BareJID, with jid: BareJID) {
            dispatcher.async {
                if let idx = self.actionQueue.firstIndex(where: { (it) -> Bool in
                    return it.equals(account: account, jid: jid);
                }) {
                    let it = self.actionQueue[idx];
                    switch it.action {
                    case .add:
                        return;
                    case .remove:
                        return;
                    case .refresh:
                        // this should not happen
                        return;
                    }
                } else {
                    self.actionQueue.append(AccountJidQueueItem(action: .refresh, account: account, jid: jid));
                }
                if self.actionQueue.count == 1{
                    self.applyActionsQueue.async {
                        self.applyActions();
                    }
                }
            }
        }
        
        func addItem(chat opened: DBChatProtocol) {
            dispatcher.async {
                print("opened chat account =", opened.account, ", jid =", opened.jid)
                if let idx = self.actionQueue.firstIndex(where: { (it) -> Bool in
                    return it.equals(chat: opened);
                }) {
                    let it = self.actionQueue[idx];
                    switch it.action {
                    case .add:
                        return;
                    case .remove:
                        self.actionQueue.remove(at: idx);
                        self.actionQueue.append(DBChatQueueItem(action: .refresh, chat: opened));
                        return;
                    case .refresh:
                        // this should not happen
                        return;
                    }
                } else {
                    self.actionQueue.append(DBChatQueueItem(action: .add, chat: opened));
                }
                if self.actionQueue.count == 1{
                    self.applyActionsQueue.async {
                        self.applyActions();
                    }
                }
            }
        }
        
        func removeItem(for account: BareJID, jid: BareJID) {
            dispatcher.async {
                if let idx = self.actionQueue.firstIndex(where: { (it) -> Bool in
                    return it.equals(account: account, jid: jid);
                }) {
                    let it = self.actionQueue[idx];
                    switch it.action {
                    case .add:
                        self.actionQueue.remove(at: idx);
                        return;
                    case .remove:
                        return;
                    case .refresh:
                        self.actionQueue.remove(at: idx);
                        self.actionQueue.append(AccountJidQueueItem(action: .remove, account: account, jid: jid));
                        return;
                    }
                } else {
                    self.actionQueue.append(AccountJidQueueItem(action: .remove, account: account, jid: jid));
                }
                if self.actionQueue.count == 1{
                    self.applyActionsQueue.async {
                        self.applyActions();
                    }
                }
            }
        }
        
        enum Action {
            case add
            case refresh
            case remove
        }
        
        class ChatsStoreQueueItem: CustomStringConvertible {
            
            let action: Action;
            
            var description: String {
                switch action {
                case .add:
                    return "add";
                case .remove:
                    return "remove";
                case .refresh:
                    return "refresh";
                }
            }
            
            init(action: Action) {
                self.action = action;
            }
            
            func equals(chat: DBChatProtocol) -> Bool {
                return false;
            }
         
            func equals(account: BareJID, jid: BareJID) -> Bool {
                return false;
            }

        }

        class DBChatQueueItem: ChatsStoreQueueItem {
            
            let chat: DBChatProtocol;
            
            override var description: String {
                return "(\(super.description), \(chat.account.stringValue), \(chat.jid.bareJid))";
            }
            
            init(action: Action, chat: DBChatProtocol) {
                self.chat = chat;
                super.init(action: action);
            }
            
            override func equals(chat: DBChatProtocol) -> Bool {
                return chat.id == self.chat.id;
            }
            
            override func equals(account: BareJID, jid: BareJID) -> Bool {
                return chat.account == account && chat.jid.bareJid == jid;
            }
            
        }
        
        class AccountJidQueueItem: ChatsStoreQueueItem {
            
            private let account: BareJID;
            private let jid: BareJID;

            override var description: String {
                return "(\(super.description), \(account.stringValue), \(jid))";
            }
            
            init(action: Action, account: BareJID, jid: BareJID) {
                self.account = account;
                self.jid = jid;
                super.init(action: action);
            }
            
            override func equals(chat: DBChatProtocol) -> Bool {
                return chat.account == account && chat.jid.bareJid == jid;
            }
            
            override func equals(account: BareJID, jid: BareJID) -> Bool {
                return self.account == account && self.jid == jid;
            }

        }

        struct ChatsStore {
            
            fileprivate var items: [DBChatProtocol] = [];
            var count: Int {
                return items.count;
            }
            
            func item(at idx: Int) -> DBChatProtocol? {
                return items[idx];
            }
            
            func indexes(for queue: [ChatsStoreQueueItem]) -> [Int] {
                var results: [Int] = [];
                for item in queue {
                    if let idx = index(for: item) {
                        results.append(idx);
                    }
                }
                return results;
            }
            
            func index(for queueItem: ChatsStoreQueueItem) -> Int? {
                return self.items.firstIndex(where: queueItem.equals(chat:));
            }
            
            mutating func remove(for indexes: [Int]) {
                indexes.sorted(by: { (i1, i2) -> Bool in
                    return i2 < i1;
                }).forEach { idx in
                    self.items.remove(at: idx)
                }
            }
            
            mutating func add(for queueItem: ChatsStoreQueueItem) -> Bool {
                guard let item = queueItem as? DBChatQueueItem else {
                    return false;
                }
                
                guard items.firstIndex(where: item.equals(chat:)) == nil else {
                    return false;
                }

                let idx = items.firstIndex(where: { (it) -> Bool in
                    it.timestamp.compare(item.chat.timestamp) == .orderedAscending;
                }) ?? items.count;
                items.insert(item.chat, at: idx);
                return true;
            }
        }

    }
    
    public enum SortOrder: String {
        case byTime
        case byAvailablityAndTime
    }
}
