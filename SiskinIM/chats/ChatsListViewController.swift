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
        NotificationCenter.default.addObserver(self, selector: #selector(ChatsListViewController.unreadCountChanged), name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: nil);
        self.updateBadge();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.navigationBar.backgroundColor = Appearance.current.controlBackgroundColor;
        super.viewWillAppear(animated);
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
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
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = Settings.EnableNewUI.getBool() ? "ChatsListTableViewCellNew" : "ChatsListTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! ChatsListTableViewCell;
        
        if let item = dataSource.item(at: indexPath) {
            cell.nameLabel.textColor = Appearance.current.labelColor;
            cell.nameLabel.font = item.unread > 0 ? UIFont.boldSystemFont(ofSize: cell.nameLabel.font.pointSize) : UIFont.systemFont(ofSize: cell.nameLabel.font.pointSize);
//            if Settings.EnableNewUI.getBool() {
                cell.lastMessageLabel.textColor = Appearance.current.labelColor;
//            } else {
            cell.lastMessageLabel.textColor = Appearance.current.secondaryLabelColor;
//            }
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
                cell.avatarStatusView.updateAvatar(manager: self.xmppService.avatarManager, for: item.account, with: room.roomJid, name: nil, orDefault: self.xmppService.avatarManager.defaultGroupchatAvatar);
                cell.avatarStatusView.setStatus(room.state == .joined ? Presence.Show.online : nil);
                cell.nameLabel.text = room.name ?? item.jid.stringValue;
            default:
                let rosterModule: RosterModule? = xmppClient?.modulesManager.getModule(RosterModule.ID);
                let rosterItem = rosterModule?.rosterStore.get(for: item.jid);
                let name = rosterItem?.name ?? item.jid.bareJid.stringValue;
                cell.nameLabel.text = name;
                cell.avatarStatusView.updateAvatar(manager: self.xmppService.avatarManager, for: item.account, with: item.jid.bareJid, name: name, orDefault: self.xmppService.avatarManager.defaultAvatar);
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
                guard let item = dataSource.item(at: indexPath) else {
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
        guard let item = dataSource.item(at: indexPath) else {
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
        
        private var items: [DBChatProtocol] = [];
        
        var count: Int {
            return items.count;
        }
        
        init(controller: ChatsListViewController) {
            self.controller = controller;
            
            NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(chatOpened), name: DBChatStore.CHAT_OPENED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(chatClosed), name: DBChatStore.CHAT_CLOSED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(chatUpdated), name: DBChatStore.CHAT_UPDATED, object: nil);
            
            dispatcher.async {
                DispatchQueue.main.sync {
                    self.items = DBChatStore.instance.getChats().sorted(by: self.chatsSorter);
                    self.controller?.tableView.reloadData();
                }
            }
        }
        
        func item(at indexPath: IndexPath) -> DBChatProtocol? {
            return items[indexPath.row];
        }
        
        func getChat(at index: Int) -> DBChatProtocol? {
            return items[index];
        }

        func chatsSorter(i1: DBChatProtocol, i2: DBChatProtocol) -> Bool {
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
            
            dispatcher.async {
                var items = DispatchQueue.main.sync { return self.items };
                guard let idx = items.firstIndex(where: { (item) -> Bool in
                    item.id == opened.id
                }) else {
                    return;
                }
                
                _ = items.remove(at: idx);
                
                DispatchQueue.main.async {
                    self.items = items;
                    self.controller?.tableView.deleteRows(at: [IndexPath(row: idx, section: 0)], with: .automatic);
                }
            }
        }
        
        @objc func chatUpdated(_ notification: Notification) {
            guard let e = notification.object as? DBChatProtocol else {
                return;
            }
            
            dispatcher.async {
                var items = DispatchQueue.main.sync { return self.items };
                guard let oldIdx = items.firstIndex(where: { (item) -> Bool in
                    item.id == e.id;
                }) else {
                    return;
                }
                
                let item = items.remove(at: oldIdx);
                
                let newIdx = items.firstIndex(where: { (it) -> Bool in
                    it.timestamp.compare(item.timestamp) == .orderedAscending;
                }) ?? items.count;
                items.insert(item, at: newIdx);
                
                if oldIdx == newIdx {
                    DispatchQueue.main.async {
                        self.items = items;
                        self.controller?.tableView.reloadRows(at: [IndexPath(row: newIdx, section: 0)], with: .automatic);
                    }
                } else {
                    DispatchQueue.main.async {
                        self.items = items;
                        self.controller?.tableView.moveRow(at: IndexPath(row: oldIdx, section: 0), to: IndexPath(row: newIdx, section: 0));
                        self.controller?.tableView.reloadRows(at: [IndexPath(row: newIdx, section: 0)], with: .automatic);
                    }
                }
            }
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
        
        func refreshItem(for account: BareJID, with jid: BareJID) {
            dispatcher.async {
                var items = DispatchQueue.main.sync { return self.items };
                guard let idx = items.firstIndex(where: { (item) -> Bool in
                    item.account == account && item.jid.bareJid == jid;
                }) else {
                    return;
                }
                
                DispatchQueue.main.async {
                    self.items = items;
                    self.controller?.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .automatic);
                }

            }
        }
        
        func addItem(chat opened: DBChatProtocol) {
            dispatcher.async {
                print("opened chat account =", opened.account, ", jid =", opened.jid)
                
                var items = DispatchQueue.main.sync { return self.items };
                
                guard items.firstIndex(where: { (item) -> Bool in
                    item.id == opened.id
                }) == nil else {
                    return;
                }
                
                let item = opened;
                let idx = items.firstIndex(where: { (it) -> Bool in
                    it.timestamp.compare(item.timestamp) == .orderedAscending;
                }) ?? items.count;
                items.insert(item, at: idx);
                
                DispatchQueue.main.async {
                    self.items = items;
                    self.controller?.tableView.insertRows(at: [IndexPath(row: idx, section: 0)], with: .automatic);
                }
            }
        }
        
        func removeItem(for account: BareJID, jid: BareJID) {
            dispatcher.async {
                var items = DispatchQueue.main.sync { return self.items };
                guard let idx = items.firstIndex(where: { (item) -> Bool in
                    item.account == account && item.jid.bareJid == jid;
                }) else {
                    return;
                }
                
                _ = items.remove(at: idx);
                
                DispatchQueue.main.async {
                    self.items = items;
                    self.controller?.tableView.deleteRows(at: [IndexPath(row: idx, section: 0)], with: .automatic);
                }
            }
        }

    }
    
    public enum SortOrder: String {
        case byTime
        case byAvailablityAndTime
    }
}

