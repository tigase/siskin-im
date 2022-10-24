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
import Martin
import Combine
import SwiftUI
import Shared

class LabelWithInsets: UILabel {
    
    var insets: UIEdgeInsets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)
    
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize;
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom);
    }
    
}

class BadgedButton: UIButton {
    
    let badgeLabel = LabelWithInsets();
    
    var badge: String? {
        didSet {
            badgeLabel.text = badge;
            isBadgeVisible = badge != nil;

            badgeLabel.sizeToFit();
            badgeLabel.layer.cornerRadius = badgeLabel.intrinsicContentSize.height / 2;
        }
    }
    
    var isBadgeVisible: Bool = false {
        didSet {
            guard oldValue != isBadgeVisible else {
                return;
            }
            
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false;
            badgeLabel.backgroundColor = UIColor.systemRed;
            badgeLabel.textColor = UIColor.white;
            badgeLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize, weight: .medium)
            badgeLabel.textAlignment = .center;
            badgeLabel.layer.masksToBounds = true;

            if isBadgeVisible {
                self.addSubview(badgeLabel);
                NSLayoutConstraint.activate([
                    badgeLabel.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 2),
                    badgeLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 2)
                ])
            } else {
                badgeLabel.removeFromSuperview();
            }
        }
    }
    
}

private var badgeHandle: UInt8 = 0

class BadgedBarButtonItem: UIBarButtonItem {

    private var badgeLayer: CAShapeLayer? {
        return objc_getAssociatedObject(self, &badgeHandle) as? CAShapeLayer;
    }

        public func setBadge(text: String?) {
            badgeLayer?.removeFromSuperlayer()

            guard let text = text, !text.isEmpty else {
                return
            }

            guard let view = self.value(forKey: "view") as? UIView else {
                return;
            }
            
            let font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular);
            let badgeSize = text.size(withAttributes: [.font: font])
            let width = max(badgeSize.width + 2, badgeSize.height)
            let badgeFrame = CGRect(origin: CGPoint(x: view.frame.width - width - 8, y: 4), size: CGSize(width: width, height: badgeSize.height))

            let layer = CAShapeLayer()
            layer.path = UIBezierPath(roundedRect: badgeFrame, cornerRadius: 7).cgPath
            layer.fillColor = UIColor.red.cgColor;
            layer.strokeColor = UIColor.red.cgColor
            
            view.layer.addSublayer(layer)

            let label = CATextLayer()
            label.string = text
            label.alignmentMode = .center
            label.font = font
            label.fontSize = font.pointSize
            label.foregroundColor = UIColor.white.cgColor

            label.frame = badgeFrame
            label.cornerRadius = label.frame.height / 2
            label.foregroundColor = UIColor.white.cgColor;
            label.backgroundColor = UIColor.clear.cgColor
            label.contentsScale = UIScreen.main.scale
            layer.addSublayer(label)
            
            objc_setAssociatedObject(self, &badgeHandle, layer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            layer.zPosition = 1000
        }
    
}

class ChatsListViewController: UITableViewController, UISearchResultsUpdating {
    
    @IBOutlet var addMucButton: UIBarButtonItem!
    @IBOutlet var settingsButton: BadgedBarButtonItem!;
    
    var dataSource: ChatsDataSource?;
    var searchController: UISearchController?;
    private let progressView: UIActivityIndicatorView = UIActivityIndicatorView(style: .large);
    
    @available(iOS 14.0, *)
    private var searchResultsView: SearchResultsView {
        get {
            return (searchController!.searchResultsController as! UIHostingController<SearchResultsView>).rootView

        }
        set {
            (searchController!.searchResultsController as! UIHostingController<SearchResultsView>).rootView = newValue;
        }
    }
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        dataSource = ChatsDataSource(controller: self);
        super.viewDidLoad();
        
        if #available(iOS 14, *) {
            progressView.hidesWhenStopped = true;
            progressView.translatesAutoresizingMaskIntoConstraints = false;
            progressView.color = UIColor.white;
            self.view.addSubview(progressView);
            NSLayoutConstraint.activate([
                progressView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                progressView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
            ]);
            searchController = UISearchController(searchResultsController: UIHostingController(rootView: SearchResultsView()));
            searchController?.searchResultsUpdater = self;
            searchController?.obscuresBackgroundDuringPresentation = true;
            searchController?.showsSearchResultsController = true;
            searchController?.searchBar.searchBarStyle = .prominent;
            searchController?.hidesNavigationBarDuringPresentation = true;
            searchController?.searchBar.isOpaque = false;
            searchController?.searchBar.autocapitalizationType = .none;
            searchController?.searchBar.autocorrectionType  = .no;
            searchController?.searchBar.isTranslucent = true;
            searchController?.searchBar.placeholder = NSLocalizedString("Chat with…", comment: "placeholder for text field to search for conversation to open")
                        
            navigationItem.searchController = searchController;
            navigationItem.hidesSearchBarWhenScrolling = true;
            searchResultsView.selection = { [weak self] selected in
                self?.searchController?.searchBar.text = "";
                self?.searchController?.dismiss(animated: true, completion: {
                    guard let account = selected.account else {
                        if let that = self {
                            AccountSelectionView.selectAccount(parentController: that, completionHandler: { account in
                                guard let client = XmppService.instance.getClient(for: account) else {
                                    return;
                                }
                                that.progressView.startAnimating();
                                Task {
                                    do {
                                        let result = try await client.module(.disco).info(for: selected.jid.jid());
                                        that.progressView.stopAnimating();
                                        if result.features.contains("urn:xmpp:mix:core:1") {
                                            // this is MIX
                                            if selected.jid.localPart == nil {
                                                let navController = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinNavigationViewController") as! UINavigationController;
                                                (navController.visibleViewController as! ChannelSelectToJoinViewController).client = client;
                                                (navController.visibleViewController as! ChannelSelectToJoinViewController).domain = selected.jid.domain;
                                                
                                                navController.modalPresentationStyle = .formSheet;
                                                that.present(navController, animated: true)
                                            } else {
                                                let controller = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinViewController") as! ChannelJoinViewController;
                                                
                                                controller.client = client;
                                                controller.channelJid = selected.jid;
                                                controller.componentType = .mix;
                                                controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: controller, action: #selector(ChannelJoinViewController.cancelClicked(_:)));
                                                
                                                let navController = UINavigationController(rootViewController: controller);
                                                navController.modalPresentationStyle = .formSheet;
                                                that.present(navController, animated: true)
                                            }
                                        } else if result.features.contains("http://jabber.org/protocol/muc") {
                                            // this is MUC
                                            if selected.jid.localPart == nil {
                                                let navController = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinNavigationViewController") as! UINavigationController;
                                                (navController.visibleViewController as! ChannelSelectToJoinViewController).client = client;
                                                (navController.visibleViewController as! ChannelSelectToJoinViewController).domain = selected.jid.domain;
                                                
                                                navController.modalPresentationStyle = .formSheet;
                                                that.present(navController, animated: true)
                                            } else {
                                                let controller = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinViewController") as! ChannelJoinViewController;
                                                
                                                controller.client = XmppService.instance.getClient(for: account);
                                                controller.channelJid = selected.jid;
                                                controller.componentType = .muc;
                                                controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: controller, action: #selector(ChannelJoinViewController.cancelClicked(_:)));
                                                
                                                let navController = UINavigationController(rootViewController: controller);
                                                navController.modalPresentationStyle = .formSheet;
                                                that.present(navController, animated: true)
                                            }
                                        } else {
                                            // this is 1-1 if it supports any messaging
                                            guard let conv = client.modulesManager.module(.message).chatManager.createChat(for: client, with: selected.jid) as? Conversation else {
                                                return;
                                            }
                                            that.openConversation(conv);
                                        }
                                    } catch {
                                        that.progressView.stopAnimating();
                                    }
                                }
                            })
                        }
                        return;
                    }
                    guard let conv = DBChatStore.instance.conversation(for: account, with: selected.jid) else {
                        guard let contact = selected.displayableId as? Contact else {
                            guard let client = XmppService.instance.getClient(for: account), let conference = client.module(.pepBookmarks).currentBookmarks.conference(for: selected.jid.jid()) else {
                                return;
                            }
                            
                            let controller = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinViewController") as! ChannelJoinViewController;
                        
                            controller.client = XmppService.instance.getClient(for: account);
                            controller.channelJid = selected.jid;
                            controller.nickname = conference.nick;
                            controller.componentType = .muc;
                            controller.password = conference.password;

                            controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: controller, action: #selector(ChannelJoinViewController.cancelClicked(_:)));
                            
                            let navController = UINavigationController(rootViewController: controller);
                            navController.modalPresentationStyle = .formSheet;
                            self?.present(navController, animated: true)
                            return;
                        }
                        guard let client = XmppService.instance.getClient(for: contact.account), let conv = client.modulesManager.module(.message).chatManager.createChat(for: client, with: contact.jid) as? Conversation else {
                            return;
                        }
                        self?.openConversation(conv);
                        return;
                    }
                    self?.openConversation(conv);
                });
            }
        }
        tableView.dataSource = self;
        setColors();
        updateNavBarColors();

        settingsButton.image = UIImage(systemName: "gear");
//        XmppService.instance.$clients.combineLatest(XmppService.instance.$connectedClients).map({ (clients, connectedClients) -> Int in
//            return (clients.count - connectedClients.count) + AccountManager.accountNames().filter({(name)->Bool in
//                return AccountSettings.lastError(for: name) != nil
//            }).count;
        XmppService.instance.$clients.combineLatest(XmppService.instance.$connectedClients).map({ (clients, connectedClients) -> Int in
            return (clients.count - connectedClients.count);
        }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] value in
            self?.settingsButton.setBadge(text: value == 0 ? nil : "\(value)")
        }).store(in: &cancellables);
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        if #available(iOS 14.0, *) {
            guard let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty else {
                searchResultsView.conversations = [];
                return;
            }
            
            let conversations: [DisplayableIdWithKeyProtocol] = DBChatStore.instance.conversations.filter({ $0.displayName.lowercased().contains(query) || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) });

            var keys = Set(conversations.map({ Contact.Key(account: $0.account, jid: $0.jid, type: .buddy) }));
                        
            let contacts: [DisplayableIdWithKeyProtocol] = DBRosterStore.instance.items.filter({ $0.name?.lowercased().contains(query) ?? false || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) }).compactMap({ item -> Contact? in
            guard let account = item.context?.userBareJid, !keys.contains(.init(account: account, jid: item.jid.bareJid, type: .buddy)) else {
                                return nil;
                            }
                return ContactManager.instance.contact(for: .init(account: account, jid: item.jid.bareJid, type: .buddy))
            });
                        
            keys = Set(keys + contacts.map({ Contact.Key(account: $0.account, jid: $0.jid, type: .buddy) }));
                    
            let bookmarks = XmppService.instance.clients.values.flatMap({ client in client.module(.pepBookmarks).currentBookmarks.items.compactMap({ $0 as? Bookmarks.Conference }).filter({ $0.name?.lowercased().contains(query) ?? false || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) }).filter({ !keys.contains(.init(account: client.userBareJid, jid: $0.jid.bareJid, type: .buddy)) }).map({ ConversationSearchResult(jid: $0.jid.bareJid, account: client.userBareJid, name: String.localizedStringWithFormat(NSLocalizedString("Join %@", comment: "action join bookmark item"), $0.name ?? $0.jid.description), displayableId: nil) }) });
                        
                        
            var items: [ConversationSearchResult] = ((contacts + conversations).map({ ConversationSearchResult(jid: $0.jid, account: $0.account, name: $0.displayName, displayableId: $0) }) + bookmarks).sorted(by: { c1, c2 -> Bool in c1.name.lowercased() < c2.name.lowercased() })
                        
//            if !closedSuggestionsList {
            items.append(ConversationSearchResult(jid: BareJID(query), account: nil, name: query, displayableId: nil));
//            }
                        
            searchResultsView.conversations = items;
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        DBChatStore.instance.unreadMessageCountPublisher.throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true).map({ $0 == 0 ? nil : "\($0)" }).sink(receiveValue: { [weak self] value in
            self?.navigationController?.tabBarItem.badgeValue = value;
        }).store(in: &cancellables);
        Settings.$recentsMessageLinesNo.removeDuplicates().receive(on: DispatchQueue.main).sink(receiveValue: { _ in
            self.tableView.reloadData();
        }).store(in: &cancellables);
        animate();
        
        if #available(iOS 14.0, *) {
            addMucButton.action = nil;
            addMucButton.target = nil;
            addMucButton.primaryAction = nil
            
            let newPrivateGC = UIAction(title: NSLocalizedString("New private group chat", comment: "label for chats list new converation action"), image: nil, handler: { action in
                let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelCreateNavigationViewController") as! UINavigationController;
                (navigation.visibleViewController as? ChannelCreateViewController)?.kind = .adhoc;
                navigation.modalPresentationStyle = .formSheet;
                self.present(navigation, animated: true, completion: nil);
            });
            
            let newPublicGC = UIAction(title: NSLocalizedString("New public group chat", comment: "label for chats list new converation action"), image: nil, handler: { action in
                let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelCreateNavigationViewController") as! UINavigationController;
                (navigation.visibleViewController as? ChannelCreateViewController)?.kind = .stable;
                navigation.modalPresentationStyle = .formSheet;
                self.present(navigation, animated: true, completion: nil);
            });
            
            let joinGC = UIAction(title: NSLocalizedString("Join group chat",  comment: "label for chats list new converation action"), image: nil, handler: { action in
                let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinNavigationViewController") as! UINavigationController;
                navigation.modalPresentationStyle = .formSheet;
                self.present(navigation, animated: true, completion: nil);
            })
            
            let deferedItems = UIDeferredMenuElement({ callback in
                if CallManager.instance != nil && !MeetEventHandler.instance.supportedAccounts.isEmpty {
                    callback([
                        UIAction(title: NSLocalizedString("Create meeting", comment: "label for chats list new converation action"), image: UIImage(systemName: "person.crop.rectangle"), handler: { action in
                            let selector = CreateMeetingViewController(style: .plain);
                            let navController = UINavigationController(rootViewController: selector);
                            self.present(navController, animated: true, completion: nil);
                        })
                    ]);
                } else {
                    callback([]);
                }
            });
            addMucButton.menu = UIMenu(title: "", children: [newPrivateGC, newPublicGC, joinGC, deferedItems]);
        }
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
        let appearance = UINavigationBarAppearance();
        appearance.configureWithDefaultBackground();
        appearance.backgroundColor = UIColor(named: "chatslistSemiBackground");
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark);
        navigationController?.navigationBar.standardAppearance = appearance;
        navigationController?.navigationBar.scrollEdgeAppearance = appearance;
        searchController?.searchBar.barStyle = .black;
        searchController?.searchBar.tintColor = UIColor.white;
        navigationController?.navigationBar.barTintColor = UIColor(named: "chatslistBackground");
        navigationController?.navigationBar.tintColor = UIColor.white;
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection);
        updateNavBarColors();
    }
    
    func updateNavBarColors() {
        searchController?.searchBar.searchTextField.textColor = UIColor.white;
        searchController?.searchBar.searchTextField.backgroundColor = (self.traitCollection.userInterfaceStyle != .dark ? UIColor.black : UIColor.white).withAlphaComponent(0.2);
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
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = dataSource!.item(at: indexPath)?.chat else {
            return nil;
        }
        
        var actions: [UIContextualAction] = [];
        switch item {
        case let room as Room:
            actions.append(UIContextualAction(style: .normal, title: NSLocalizedString("Leave", comment: "button label"), handler: { (action, view, completion) in
                Task {
                    do {
                        try await room.context?.module(.pepBookmarks).setConferenceAutojoin(false, for: JID(room.jid))
                        try await room.context?.module(.muc).leave(room: room);
                        do {
                            if try await room.checkTigasePushNotificationRegistrationStatus() {
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(title: NSLocalizedString("Push notifications", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("You've left there room %@ and push notifications for this room were disabled!\nYou may need to reenable them on other devices.", comment: "alert body"), room.name ?? room.roomJid.description), preferredStyle: .actionSheet);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                                    alert.popoverPresentationController?.sourceView = self.view;
                                    alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);
                                    self.present(alert, animated: true, completion: nil);
                                }
                            }
                        } catch {}
                        DispatchQueue.main.async {
                            self.discardNotifications(for: room);
                            completion(true);
                        }
                    } catch {
                        completion(false)
                    }
                }
            }))
            if room.affiliation == .owner {
                actions.append(UIContextualAction(style: .destructive, title: NSLocalizedString("Destroy", comment: "button label"), handler: { (action, view, completion) in
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: NSLocalizedString("Channel destuction", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("You are about to destroy channel %@. This will remove the channel on the server, remove remote history archive, and kick out all participants. Are you sure?", comment: "alert body"), room.roomJid.description), preferredStyle: .actionSheet);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .destructive, handler: { action in
                            Task {
                                try await room.context?.module(.pepBookmarks).remove(bookmark: Bookmarks.Conference(name: item.jid.localPart!, jid: JID(room.jid), autojoin: false));
                            }
                            room.context?.module(.muc).destroy(room: room);
                            self.discardNotifications(for: room);
                            completion(true);
                        }));
                        alert.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .default, handler: { action in
                            completion(false)
                        }))
                        alert.popoverPresentationController?.sourceView = self.view;
                        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);
                        self.present(alert, animated: true, completion: nil);
                    }
                }))
            }
        case let chat as Chat:
            actions.append(UIContextualAction(style: .normal, title: NSLocalizedString("Close", comment: "button label"), handler: { (action, view, completion) in
                let result = DBChatStore.instance.close(chat: chat);
                if result {
                    self.discardNotifications(for: chat);
                }
                completion(result);
            }))
        case let channel as Channel:
            actions.append(UIContextualAction(style: .normal, title: NSLocalizedString("Close", comment: "button label"), handler: { (action, view, completion) in
                if let mixModule = channel.context?.module(.mix), let userJid = channel.context?.userBareJid {
                    let leaveFn: () async throws -> Void = {
                        do {
                            _ = try await mixModule.leave(channel: channel);
                            self.discardNotifications(for: channel);
                            completion(true);
                        } catch {
                            completion(false);
                        }
                    }
                    Task {
                        do {
                            let data = try await mixModule.config(for: channel.channelJid);
                            if let admins = data.owner, admins.contains(JID(userJid)) && admins.count == 1 {
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(title: NSLocalizedString("Leaving channel", comment: "leaving channel title"), message: NSLocalizedString("You are the last person with ownership of this channel. Please decide what to do with the channel.", comment: "leaving channel text"), preferredStyle: .actionSheet);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("Destroy", comment: "button label"), style: .destructive, handler: { _ in
                                        Task {
                                            do {
                                                try await mixModule.destroy(channel: channel.channelJid);
                                            } catch {
                                                DispatchQueue.main.async {
                                                    let err = error as? XMPPError ?? .undefined_condition;
                                                    let alert = UIAlertController(title: NSLocalizedString("Channel destruction failed!", comment: "alert window title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to destroy channel %@. Server returned an error: %@", comment: "alert window message"), channel.name ?? channel.channelJid.description, err.localizedDescription), preferredStyle: .alert)
                                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Button"), style: .default, handler: nil));
                                                    self.present(alert, animated: true, completion: nil);
                                                }
                                            }
                                        }
                                    }));
                                    let otherParticipants = channel.participants.filter({ $0.jid != nil && $0.jid != userJid });
                                    if !otherParticipants.isEmpty {
                                        alert.addAction(UIAlertAction(title: NSLocalizedString("Pass ownership", comment: "button label"), style: .default, handler: { _ in
                                            if let navController = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelSelectNewOwnerViewNavController") as? UINavigationController, let controller = navController.visibleViewController as? ChannelSelectNewOwnerViewController {
                                                controller.channel = channel;
                                                controller.participants = otherParticipants.sorted(by: { p1, p2 in
                                                    return p1.nickname ?? p1.jid?.description ?? p1.id < p2.nickname ?? p2.jid?.description ?? p2.id;
                                                });
                                                controller.completionHandler = { result in
                                                    guard let participant = result, let jid = participant.jid else {
                                                        completion(false);
                                                        return;
                                                    }
                                                    data.owner = admins.filter({ $0.bareJid != userJid }) + [JID(jid)];
                                                    Task {
                                                        do {
                                                            try await mixModule.config(data, for: channel.channelJid);
                                                            try await leaveFn();
                                                        } catch {
                                                            completion(false)
                                                        }
                                                    }
                                                }
                                                self.present(navController, animated: true, completion: nil);
                                            }
                                        }));
                                    }
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("Leave", comment: "button label"), style: .default, handler: { _ in
                                        Task {
                                            try await leaveFn();
                                        }
                                    }))
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
                                        completion(false);
                                    }))

                                    alert.popoverPresentationController?.sourceView = self.view;
                                    alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);

                                    self.present(alert, animated: true, completion: nil);
                                }
                            } else {
                                try await leaveFn();
                            }
                        } catch {
                            try await leaveFn();
                        }
                    }
                } else {
                    completion(false);
                }
            }))
            if channel.permissions?.contains(.changeConfig) ?? false {
                actions.append(UIContextualAction(style: .destructive, title: NSLocalizedString("Destroy", comment: "button label"), handler: { (action, view, completion) in
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: NSLocalizedString("Channel destuction", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("You are about to destroy channel %@. This will remove the channel on the server, remove remote history archive, and kick out all participants. Are you sure?", comment: "alert body"), channel.channelJid.description), preferredStyle: .actionSheet);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .destructive, handler: { action in
                            Task {
                                do {
                                    try await channel.context?.module(.mix).destroy(channel: channel.channelJid);
                                    self.discardNotifications(for: channel);
                                    completion(true)
                                } catch {
                                    completion(false);
                                }
                            }
                        }));
                        alert.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .default, handler: { action in
                            completion(false)
                        }))
                        alert.popoverPresentationController?.sourceView = self.view;
                        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath);
                        self.present(alert, animated: true, completion: nil);
                    }
                }))
            }
        default:
            return nil;
        }
        
        let config = UISwipeActionsConfiguration(actions: actions);
        config.performsFirstActionWithFullSwipe = actions.count == 1;
        return config;
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = dataSource!.item(at: indexPath)?.chat else {
            return nil;
        }
        switch item {
        case let chat as Chat:
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: contextMenuActionProvider(for: chat));
        default:
            return nil;
        }
    }
    
    private func contextMenuActionProvider(for chat: Chat) -> UIContextMenuActionProvider? {
        return { suggestedActions -> UIMenu? in
            var actions: [UIMenuElement] = [];
            
            if let context = chat.context, let blockingModule = chat.context?.module(.blockingCommand), blockingModule.isAvailable {
                if blockingModule.blockedJids?.contains(JID(chat.jid)) ?? false {
                    actions.append(UIAction(title: NSLocalizedString("Unblock", comment: "context menu action"), image: UIImage(systemName: "hand.raised"), handler: { _ in
                        blockingModule.unblock(jids: [JID(chat.jid)], completionHandler: { _ in })
                    }))
                } else if blockingModule.blockedJids?.contains(JID(chat.jid.domain)) ?? false {
                    actions.append(UIAction(title: NSLocalizedString("Unblock server", comment: "context menu action"), image: UIImage(systemName: "hand.raised"), handler: { _ in
                        let alert = UIAlertController(title: NSLocalizedString("Server is blocked", comment: "alert title - unblock communication with server"), message: String.localizedStringWithFormat(NSLocalizedString("All communication with users from %@ is blocked. Do you wish to unblock communication with this server?", comment: "alert message - unblock communication with server"), chat.jid.domain), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("Unblock", comment: "unblock server"), style: .default, handler: { _ in
                            blockingModule.unblock(jids: [JID(chat.jid.domain), JID(chat.jid)], completionHandler: { _ in })
                        }))
                        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "cancel operation"), style: .cancel, handler: { _ in }))
                        self.present(alert, animated: true);
                    }))
                } else {
                    var items = [UIMenuElement]();
                    if blockingModule.isReportingSupported {
                        items.append(UIAction(title: NSLocalizedString("Report spam", comment: "context menu action"), attributes: .destructive, handler: { _ in
                            blockingModule.block(jid: JID(chat.jid), report: .init(cause: .spam), completionHandler: { _ in });
                        }));
                        
                        items.append(UIAction(title: NSLocalizedString("Report abuse", comment: "context menu action"), attributes: .destructive, handler: { _ in
                            blockingModule.block(jid: JID(chat.jid), report: .init(cause: .abuse), completionHandler: { _ in });
                        }));
                    } else {
                        items.append(UIAction(title: NSLocalizedString("Block contact", comment: "context menu item"), attributes: .destructive, handler: { _ in
                            blockingModule.block(jid: JID(chat.jid), completionHandler: { result in
                                switch result {
                                case .success(_):
                                    _ = DBChatStore.instance.close(chat: chat);
                                case .failure(_):
                                    break;
                                }
                            })
                        }))
                    }
                    items.append(UIAction(title: NSLocalizedString("Block server", comment: "context menu item"), attributes: .destructive, handler: { _ in
                        blockingModule.block(jid: JID(chat.jid.domain), completionHandler: { result in
                            switch result {
                            case .success(_):
                                let blockedChats = DBChatStore.instance.chats(for: context).filter({ $0.jid.domain == chat.jid.domain });
                                for blockedChat in blockedChats {
                                    _ = DBChatStore.instance.close(chat: blockedChat);
                                }
                            case .failure(_):
                                break;
                            }
                        })
                    }))
                    items.append(UIAction(title: NSLocalizedString("Cancel", comment: "context menu action"), handler: { _ in }));
                    actions.append(UIMenu(title: NSLocalizedString("Report & block…", comment: "context action label"), image: UIImage(systemName: "hand.raised"), children: items));
                }
            }
            
            guard !actions.isEmpty else {
                return nil;
            }
            
            return UIMenu(title: "", children: actions);
        }
    }
    
    func discardNotifications(for item: Conversation) {
        let accountStr = item.account.description.lowercased();
        let jidStr = item.jid.description.lowercased();
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
        
        openConversation(item);
    }
    
    private func openConversation(_ item: Conversation) {
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
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
        controller.popoverPresentationController?.barButtonItem = sender;
        
        controller.addAction(UIAlertAction(title: NSLocalizedString("New private group chat", comment: "label for chats list new converation action"), style: .default, handler: { action in
            let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelCreateNavigationViewController") as! UINavigationController;
            (navigation.visibleViewController as? ChannelCreateViewController)?.kind = .adhoc;
            navigation.modalPresentationStyle = .formSheet;
            self.present(navigation, animated: true, completion: nil);
        }));
        controller.addAction(UIAlertAction(title: NSLocalizedString("New public group chat", comment: "label for chats list new converation action"), style: .default, handler: { action in
            let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelCreateNavigationViewController") as! UINavigationController;
            (navigation.visibleViewController as? ChannelCreateViewController)?.kind = .stable;
            navigation.modalPresentationStyle = .formSheet;
            self.present(navigation, animated: true, completion: nil);
        }));
        
        controller.addAction(UIAlertAction(title: NSLocalizedString("Join group chat", comment: "label for chats list new converation action"), style: .default, handler: { action in
            let navigation = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinNavigationViewController") as! UINavigationController;
            navigation.modalPresentationStyle = .formSheet;
            self.present(navigation, animated: true, completion: nil);
        }));
        
        if CallManager.instance != nil && !MeetEventHandler.instance.supportedAccounts.isEmpty {
            controller.addAction(UIAlertAction(title: NSLocalizedString("Create meeting", comment: "label for chats list new converation action"), style: .default, handler: { action in
                let selector = CreateMeetingViewController(style: .plain);
                let navController = UINavigationController(rootViewController: selector);
                self.present(navController, animated: true, completion: nil);
            }))
        }
        
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        
        self.present(controller, animated: true, completion: nil);
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
            
            DBChatStore.instance.conversationsPublisher.throttleFixed(for: 0.1, scheduler: self.dispatcher, latest: true).sink(receiveValue: { [weak self] items in
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
            
            let updateFn = {
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

            if #available(iOS 13.2, *) {
                DispatchQueue.main.sync {
                    updateFn();
                }
            } else {
                updateFn();
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
