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
import Combine

class ChatsListViewController: UITableViewController {
    
    @IBOutlet var addMucButton: UIBarButtonItem!
    
    var dataSource: ChatsDataSource?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        dataSource = ChatsDataSource(controller: self);
        super.viewDidLoad();
        
        tableView.rowHeight = UITableView.automaticDimension;
        tableView.estimatedRowHeight = 66.0;
        tableView.dataSource = self;
        setColors();

//        DBChatStore.instance.$unreadMessagesCount.throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true).map({ $0 == 0 ? nil : "\($0)" }).sink(receiveValue: { [weak self] value in
//            print("setting badge to:", value, "on:", self?.navigationController, ",", self?.navigationController?.tabBarItem);
//            self?.navigationController?.tabBarItem.badgeValue = value;
//        }).store(in: &cancellables);//.assign(to: \.badgeValue, on: tabBarItem).store(in: &cancellables);
//        if let tabBarItem = self.navigationController?.tabBarItem {
//            
//        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        DBChatStore.instance.$unreadMessagesCount.throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true).map({ $0 == 0 ? nil : "\($0)" }).sink(receiveValue: { [weak self] value in
            self?.navigationController?.tabBarItem.badgeValue = value;
        }).store(in: &cancellables);
        animate();
    }
    
    private func animate() {
        guard let coordinator = self.transitionCoordinator else {
            return;
        }
        coordinator.animate(alongsideTransition: { [weak self] context in
            self?.setColors();
        }, completion: nil);
    }
    
    private func setColors() {
        navigationController?.navigationBar.barTintColor = UIColor(named: "chatslistBackground");
        navigationController?.navigationBar.tintColor = UIColor.white;
    }

    override func viewDidDisappear(_ animated: Bool) {
        cancellables.removeAll();
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
        return dataSource?.count ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = Settings.recentsMessageLinesNo == 1 ? "ChatsListTableViewCellNew" : "ChatsListTableViewCellBig";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! ChatsListTableViewCell;
        
        if let item = dataSource?.item(at: indexPath) {
            cell.update(conversation: item.chat);
        }
        cell.avatarStatusView.updateCornerRadius();
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
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
                guard let item = dataSource!.item(at: indexPath)?.chat else {
                    return;
                }
                
                var discardNotifications = false;
                switch item {
                case let room as Room:
                    if room.affiliation == .owner {
                        let alert = UIAlertController(title: "Delete group chat?", message: "You are leaving the group chat \(room.name ?? room.roomJid.stringValue)", preferredStyle: .actionSheet);
                        alert.addAction(UIAlertAction(title: "Leave chat", style: .default, handler: { (action) in
                            PEPBookmarksModule.remove(from: item.account, bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: JID(room.jid), autojoin: false));
                            room.context?.module(.muc).leave(room: room);
                            self.discardNotifications(for: item);
                        }))
                        alert.addAction(UIAlertAction(title: "Delete chat", style: .destructive, handler: { (action) in
                            PEPBookmarksModule.remove(from: item.account, bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: JID(room.jid), autojoin: false));
                            room.context?.module(.muc).destroy(room: room);
                            self.discardNotifications(for: item);
                        }));
                        alert.popoverPresentationController?.sourceView = self.view;
                        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);
                        self.present(alert, animated: true, completion: nil);
                    } else {
                        PEPBookmarksModule.remove(from: item.account, bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: JID(room.jid), autojoin: false));
                        room.context?.module(.muc).leave(room: room);

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
                                        let alert = UIAlertController(title: "Push notifications", message: "You've left there room \(room.name ?? room.roomJid.stringValue) and push notifications for this room were disabled!\nYou may need to reenable them on other devices.", preferredStyle: .actionSheet);
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
                case let chat as Chat:
                    if DBChatStore.instance.close(chat: chat) {
                        discardNotifications = true;
                    }
                case let channel as Channel:
                    if let mixModule = channel.context?.module(.mix) {
                        mixModule.leave(channel: channel, completionHandler: { result in
                            switch result {
                            case .success(_):
                                self.discardNotifications(for: item);
                            case .failure(_):
                                break;
                            }
                        });
                    }
                default:
                    break;
                }
                
                if discardNotifications {
                    self.discardNotifications(for: item);
                }
            }
        }
    }
    
    func discardNotifications(for item: Conversation) {
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
        guard let item = dataSource!.item(at: indexPath)?.chat else {
            return;
        }
        var identifier: String!;
        var controller: UIViewController? = nil;
        switch item {
        case is Room:
            identifier = "RoomViewNavigationController";
            controller = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: identifier);
        case is Channel:
            identifier = "ChannelViewNavigationController";
            controller = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: identifier);
        default:
            identifier = "ChatViewNavigationController";
            controller = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: identifier);
        }
        
        let navigationController = controller as? UINavigationController;
        let destination = navigationController?.visibleViewController ?? controller;
            
        if let baseChatViewController = destination as? BaseChatViewController {
            baseChatViewController.conversation = item;
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
            let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelCreateNavigationViewController") as! UINavigationController;
            (navigation.visibleViewController as? ChannelCreateViewController)?.kind = .adhoc;
            navigation.modalPresentationStyle = .formSheet;
            self.present(navigation, animated: true, completion: nil);
        }));
        controller.addAction(UIAlertAction(title: "New public group chat", style: .default, handler: { action in
            let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelCreateNavigationViewController") as! UINavigationController;
            (navigation.visibleViewController as? ChannelCreateViewController)?.kind = .stable;
            navigation.modalPresentationStyle = .formSheet;
            self.present(navigation, animated: true, completion: nil);
        }));
        
        controller.addAction(UIAlertAction(title: "Join group chat", style: .default, handler: { action in
            let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinNavigationViewController") as! UINavigationController;
            navigation.modalPresentationStyle = .formSheet;
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
                if controller.conversation.account == account && controller.conversation.jid == jid {
                    self.showDetailViewController(self.storyboard!.instantiateViewController(withIdentifier: "emptyDetailViewController"), sender: self);
                }
            }
        }
    }
        
    struct ConversationItem: Hashable {
        
        static func == (lhs: ConversationItem, rhs: ConversationItem) -> Bool {
            return lhs.chat.id == rhs.chat.id;
        }
        
        var name: String {
            return chat.displayName;
        }
        let chat: Conversation;
        
        let timestamp: Date;
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(chat.id);
        }
    }
    
    class ChatsDataSource {
        
        weak var controller: ChatsListViewController?;

        fileprivate var dispatcher = DispatchQueue(label: "chats_data_source", qos: .background);
                
        var count: Int {
            self.items.count;
        }
        
        private var items: [ConversationItem] = [];
        private var cancellables: Set<AnyCancellable> = [];
        
        init(controller: ChatsListViewController) {
            self.controller = controller;
            
            DBChatStore.instance.$conversations.throttle(for: 0.1, scheduler: self.dispatcher, latest: true).sink(receiveValue: { [weak self] items in
                self?.update(items: items);
            }).store(in: &cancellables);
        }
        
        func update(items: [Conversation]) {
            let newItems = items.map({ conversation in ConversationItem(chat: conversation, timestamp: conversation.timestamp) }).sorted(by: { (c1,c2) in c1.timestamp > c2.timestamp });
            let oldItems = self.items;
            
            let diffs = newItems.difference(from: oldItems).inferringMoves();
            var removed: [Int] = [];
            var inserted: [Int] = [];
            var moved: [(Int,Int)] = [];
            for action in diffs {
                switch action {
                case .remove(let offset, _, let to):
                    if let idx = to {
                        moved.append((offset, idx));
                    } else {
                        removed.append(offset);
                    }
                case .insert(let offset, _, let from):
                    if from == nil {
                        inserted.append(offset);
                    }
                }
            }
            
            guard (!removed.isEmpty) || (!moved.isEmpty) || (!inserted.isEmpty) else {
                return;
            }
            
            DispatchQueue.main.sync {
                self.items = newItems;
                self.controller?.tableView.beginUpdates();
                if !removed.isEmpty {
                    self.controller?.tableView.deleteRows(at: removed.map({ IndexPath(row: $0, section: 0) }), with: .fade);
                }
                for (from,to) in moved {
                    self.controller?.tableView.moveRow(at: IndexPath(row: from, section: 0), to: IndexPath(row: to, section: 0));
                }
                if !inserted.isEmpty {
                    self.controller?.tableView.insertRows(at: inserted.map({ IndexPath(row: $0, section: 0) }), with: .fade);
                }
                self.controller?.tableView.endUpdates();
            }
        }
                
        func item(at indexPath: IndexPath) -> ConversationItem? {
            return self.items[indexPath.row];
        }
        
        func item(at index: Int) -> ConversationItem? {
            return self.items[index];
        }
    }
}
