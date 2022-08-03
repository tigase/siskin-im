//
// BookmarksController.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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
import Martin
import Combine

public class BookmarksController: UITableViewController {
    
    private var items: [BookmarkItem] = [] {
        didSet {
            self.tableView.reloadData();
        }
    }
    
    private var clientCancellable: AnyCancellable?;
    private var cancellables: Set<AnyCancellable> = [];
    
    public override func viewDidLoad() {
        super.viewDidLoad();
        setColors();
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        clientCancellable = XmppService.instance.$clients.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] clients in
            guard let that = self else {
                return;
            }
            that.cancellables.removeAll()
            that.items = [];
            for client in clients.values {
                let account = client.userBareJid;
                client.module(.pepBookmarks).$currentBookmarks.receive(on: DispatchQueue.main).sink(receiveValue: { bookmarks in
                    guard let that = self else {
                        return;
                    }
                    that.items = (that.items.filter({ $0.account != account }) + bookmarks.items.compactMap({ $0 as? Bookmarks.Conference }).map({ BookmarkItem(account: account, item: $0) })).sorted(by: { b1, b2 in b1.name < b2.name });
                }).store(in: &that.cancellables)
            }
        });
        animate();
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        clientCancellable = nil;
        cancellables.removeAll();
        items.removeAll();
        super.viewDidDisappear(animated);
    }
    
    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count;
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bookmarkCell", for: indexPath) as! BookmarkViewCell;
        cell.bookmark = items[indexPath.row];
        return cell;
    }
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        guard items.count > indexPath.row else {
            return;
        }
        
        let item = items[indexPath.row];
        
        join(bookmark: item);
    }
    
    public override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard items.count > indexPath.row else {
            return nil;
        }
        
        let item = items[indexPath.row];
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions -> UIMenu? in
            var items = [
                UIAction(title: NSLocalizedString("Join", comment: "button label"), image: UIImage(systemName: "person.badge.plus"), handler: { action in
                    self.join(bookmark: item);
                })
            ];
            
            if (item.autojoin) {
                items.append(UIAction(title: NSLocalizedString("Disable autojoin", comment: "button label"), image: UIImage(systemName: "star.slash"), handler: { action in
                    self.pepBookmarksModule(for: item.account)?.setConferenceAutojoin(false, for: item.jid);
                }));
            } else {
                items.append(UIAction(title: NSLocalizedString("Enable autojoin", comment: "button label"), image: UIImage(systemName: "star"), handler: { action in
                    self.pepBookmarksModule(for: item.account)?.setConferenceAutojoin(true, for: item.jid);
                }));
            }
            items.append(UIAction(title: NSLocalizedString("Delete", comment: "button label"), image: UIImage(systemName: "trash"), attributes: .destructive, handler: { action in
                self.pepBookmarksModule(for: item.account)?.remove(bookmark: item.item);
            }));
            return UIMenu(title: "", children: items);
        };
    }
    
    private func pepBookmarksModule(for account: BareJID) -> PEPBookmarksModule? {
        return XmppService.instance.getClient(for: account)?.module(.pepBookmarks);
    }
    
    private func join(bookmark item: BookmarkItem) {
        guard let conversation = DBChatStore.instance.conversation(for: item.account, with: item.jid.bareJid) else {
            guard let client = XmppService.instance.getClient(for: item.account), client.isConnected else {
                return;
            }
            let joinController = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinViewController") as! ChannelJoinViewController;
            joinController.fromBookmark = true;
            joinController.client = client;
            joinController.channelJid = item.jid.bareJid;
            joinController.name = item.name;
            joinController.componentType = .muc;
            joinController.password = item.password;
            joinController.nickname = item.nickname;
            
            joinController.onConversationJoined = { conversation in
                self.open(conversation: conversation);
            }

            joinController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: joinController, action: #selector(ChannelJoinViewController.cancelClicked(_:)));
            
            joinController.hidesBottomBarWhenPushed = true;
            
            let navController = UINavigationController(rootViewController: joinController);
            navController.modalPresentationStyle = .formSheet;
            self.present(navController, animated: true, completion: nil);
            return;
        }
        self.open(conversation: conversation);
    }
    
    private func open(conversation: Conversation) {
        guard conversation is Room else {
            return;
        }
        let controller = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "RoomViewNavigationController");
        let destination = ((controller as? UINavigationController)?.visibleViewController ?? controller) as! BaseChatViewController;
            
        destination.conversation = conversation;
        destination.hidesBottomBarWhenPushed = true;
            
        self.showDetailViewController(controller, sender: self);
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
        navigationController?.navigationBar.barTintColor = UIColor(named: "chatslistBackground")?.withAlphaComponent(0.2);
        navigationController?.navigationBar.tintColor = UIColor.white;
    }
    
}
