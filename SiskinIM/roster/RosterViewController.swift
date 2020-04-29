//
// RosterViewController.swift
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

class RosterViewController: AbstractRosterViewController, UIGestureRecognizerDelegate {

    var availabilityFilterSelector: UISegmentedControl?;
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchBar.delegate = self;
        searchController.searchBar.scopeButtonTitles = ["By name", "By status"];
        
        // Do any additional setup after loading the view, typically from a nib.
        if #available(iOS 13.0, *) {            
        } else {
            let lpgr = UILongPressGestureRecognizer(target: self, action: #selector(RosterViewController.handleLongPress));
            lpgr.minimumPressDuration = 1.0;
            lpgr.delegate = self;
            tableView.addGestureRecognizer(lpgr);
        }

        navigationItem.leftBarButtonItem = self.editButtonItem
        availabilityFilterSelector = UISegmentedControl(items: ["All", "Available"]);
        navigationItem.titleView = availabilityFilterSelector;
        availabilityFilterSelector?.selectedSegmentIndex = Settings.RosterAvailableOnly.getBool() ? 1 : 0;
        availabilityFilterSelector?.addTarget(self, action: #selector(RosterViewController.availabilityFilterChanged), for: .valueChanged);
        
        setColors();
        updateNavBarColors();
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)), name: Settings.SETTINGS_CHANGED, object: nil);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
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
//        navigationController?.navigationBar.barStyle = .black;
//        navigationController?.navigationBar.isTranslucent = true;
        searchController.searchBar.barStyle = .black;
        searchController.searchBar.tintColor = UIColor.white;
        navigationController?.navigationBar.barTintColor = UIColor(named: "chatslistBackground")?.withAlphaComponent(0.2);
        navigationController?.navigationBar.tintColor = UIColor.white;
        if #available(iOS 13.0, *) {
//            (navigationItem.titleView as? UISegmentedControl)?.selectedSegmentTintColor =
        } else {
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection);
        updateNavBarColors();
    }
    
    func updateNavBarColors() {
        if #available(iOS 13.0, *) {
            if self.traitCollection.userInterfaceStyle == .dark {
                availabilityFilterSelector?.setTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .selected);
                availabilityFilterSelector?.setTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .normal);
                searchController.searchBar.setScopeBarButtonTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .selected)
                searchController.searchBar.setScopeBarButtonTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .normal);
            } else {
                availabilityFilterSelector?.setTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor(named: "chatslistBackground")!], for: .selected);
                availabilityFilterSelector?.setTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .normal);
                searchController.searchBar.setScopeBarButtonTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor(named: "chatslistBackground")!], for: .selected)
                searchController.searchBar.setScopeBarButtonTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .normal);
            }
            searchController.searchBar.searchTextField.textColor = UIColor.white;
            searchController.searchBar.searchTextField.backgroundColor = (self.traitCollection.userInterfaceStyle != .dark ? UIColor.black : UIColor.white).withAlphaComponent(0.2);
            DispatchQueue.main.async {
                self.availabilityFilterSelector?.selectedSegmentIndex = Settings.RosterAvailableOnly.getBool() ? 1 : 0;
            }
        }
    }
    
    @objc func settingsChanged(_ notification: Notification) {
        guard let setting = Settings(rawValue: (notification.userInfo?["key"] as? String) ?? ""), setting == Settings.RosterType else {
            return;
        }
        DispatchQueue.main.async {
            self.initializeRosterProvider(availableOnly: (self.availabilityFilterSelector?.selectedSegmentIndex ?? 0) == 1, sortOrder: self.searchController.searchBar.selectedScopeButtonIndex == 0 ? .alphabetical : .availability);
            self.tableView.reloadData();
        }
    }
    
    override func initializeRosterProvider(availableOnly: Bool, sortOrder: RosterSortingOrder) {
        let order = RosterSortingOrder(rawValue: Settings.RosterItemsOrder.getString() ?? "") ?? .alphabetical;
        super.initializeRosterProvider(availableOnly: Settings.RosterAvailableOnly.getBool(), sortOrder: order);
        
        switch order {
        case .alphabetical:
            searchController.searchBar.selectedScopeButtonIndex = 0;
        case .availability:
            searchController.searchBar.selectedScopeButtonIndex = 1;
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "RosterItemTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! RosterItemTableViewCell;
        
        if let item = roster?.item(at: indexPath) {
            cell.nameLabel.text = item.displayName;
            cell.statusLabel.text = item.presence?.status ?? item.jid.stringValue;
            cell.avatarStatusView.setStatus(item.presence?.show);
            cell.avatarStatusView.set(name: item.displayName, avatar: AvatarManager.instance.avatar(for: item.jid.bareJid, on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
        }
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = roster?.item(at: indexPath) else {
            return;
        }
        createChat(for: item);
    }

    private func createChat(for item: RosterProviderItem) {
        let xmppClient = XmppService.instance.getClient(forJid: item.account);
        let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
        
        guard messageModule != nil else {
            return;
        }
        
        let chat = DBChatStore.instance.getChat(for: item.account, with: item.jid.bareJid) ?? (messageModule!.chatManager!.getChatOrCreate(with: item.jid, thread: nil) as! DBChat);
        
        switch chat {
        case is DBChat:
            let destination = self.storyboard!.instantiateViewController(withIdentifier: "ChatViewNavigationController") as! UINavigationController;
            let chatController = destination.children[0] as! ChatViewController;
            chatController.hidesBottomBarWhenPushed = true;
            chatController.account = item.account;
            chatController.jid = item.jid.bareJid;
            self.showDetailViewController(destination, sender: self);
        case is DBRoom:
            let destination = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "RoomViewNavigationController") as! UINavigationController;
            let chatController = destination.children[0] as! MucChatViewController;
            chatController.hidesBottomBarWhenPushed = true;
            chatController.account = item.account;
            chatController.jid = item.jid.bareJid;
            self.showDetailViewController(destination, sender: self);
        case is DBChannel:
            let destination = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelViewNavigationController") as! UINavigationController;
            let chatController = destination.children[0] as! ChannelViewController;
            chatController.hidesBottomBarWhenPushed = true;
            chatController.account = item.account;
            chatController.jid = item.jid.bareJid;
            self.showDetailViewController(destination, sender: self);
        default:
            break;
        }
        
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let item = roster?.item(at: indexPath) else {
                return;
            }
            let account: BareJID = item.account;
            let jid: JID = item.jid;
            self.deleteItem(for: account, jid: jid);
        }
    }
    
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard let item = self.roster?.item(at: indexPath) else {
            return nil;
        }
        return [UITableViewRowAction(style: .destructive, title: "Delete", handler: {(action, path) in
            print("deleting record at", path);
            self.deleteItem(for: item.account, jid: item.jid);
        }),UITableViewRowAction(style: .normal, title: "Edit", handler: {(action, path) in
            print("editing record at ", path);
            self.openEditItem(for: item.account, jid: item.jid);
        })];
    }
    
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        let order: RosterSortingOrder = selectedScope == 0 ? .alphabetical : .availability;
        roster?.order = order;
        Settings.RosterItemsOrder.setValue(order.rawValue);
        tableView.reloadData();
    }
    
    @objc func availabilityFilterChanged(_ control: UISegmentedControl) {
        let availableOnly = control.selectedSegmentIndex == 1;
        self.roster?.availableOnly = availableOnly;
        Settings.RosterAvailableOnly.setValue(availableOnly);
        tableView.reloadData();
    }
    
    @objc func handleLongPress(_ gestureRecognizer:UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else {
            if gestureRecognizer.state == .ended {
                let point = gestureRecognizer.location(in: self.tableView);
                if let indexPath = self.tableView.indexPathForRow(at: point) {
                    self.tableView.deselectRow(at: indexPath, animated: true);
                }
            }
            return;
        }

        let point = gestureRecognizer.location(in: self.tableView);
        if let indexPath = self.tableView.indexPathForRow(at: point) {
            print("long press detected at", indexPath);

            guard let item = roster?.item(at: indexPath) else {
                return;
            }
            
            let alert = UIAlertController(title: item.displayName, message: "using \(item.account.stringValue)", preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Chat", style: .default, handler: { (action) in
                self.tableView(self.tableView, didSelectRowAt: indexPath);
            }));
            #if targetEnvironment(simulator)
            #else
            let jingleSupport = JingleManager.instance.support(for: item.jid, on: item.account);
            if jingleSupport.contains(.audio) && jingleSupport.contains(.video) {
                alert.addAction(UIAlertAction(title: "Video call", style: .default, handler: { (action) in
                    VideoCallController.call(jid: item.jid.bareJid, from: item.account, media: [.audio, .video], sender: self);
                }));
            }
            if jingleSupport.contains(.audio) {
                alert.addAction(UIAlertAction(title: "Audio call", style: .default, handler: { (action) in
                    VideoCallController.call(jid: item.jid.bareJid, from: item.account, media: [.audio], sender: self);
                }));
            }
            #endif
            alert.addAction(UIAlertAction(title: "Edit", style: .default, handler: {(action) in
                self.openEditItem(for: item.account, jid: item.jid);
            }));
            alert.addAction(UIAlertAction(title: "Info", style: .default, handler: {(alert) in
                self.showItemInfo(for: item.account, jid: item.jid);
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            alert.popoverPresentationController?.sourceView = self.tableView;
            alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);
            self.present(alert, animated: true, completion: nil);
        }
    }
    
    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = roster?.item(at: indexPath) else {
            return nil;
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions -> UIMenu? in
            return self.prepareContextMenu(item: item);
        };
    }
    
//    @available(iOS 13.0, *)
//    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
//        var cfg = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions -> UIMenu? in
//            return self.prepareContextMenu();
//        };
//        return cfg;
//    }
    
    @available(iOS 13.0, *)
    func prepareContextMenu(item: RosterProviderItem) -> UIMenu {
        var items = [
            UIAction(title: "Chat", image: UIImage(systemName: "message"), handler: { action in
                self.createChat(for: item);
            })
        ];
        #if targetEnvironment(simulator)
        #else
        let jingleSupport = JingleManager.instance.support(for: item.jid, on: item.account);
        if jingleSupport.contains(.audio) && jingleSupport.contains(.video) {
            items.append(UIAction(title: "Video call", image: UIImage(systemName: "video"), handler: { (action) in
                VideoCallController.call(jid: item.jid.bareJid, from: item.account, media: [.audio, .video], sender: self);
            }));
        }
        if jingleSupport.contains(.audio) {
            items.append(UIAction(title: "Audio call", image: UIImage(systemName: "phone"), handler: { (action) in
                VideoCallController.call(jid: item.jid.bareJid, from: item.account, media: [.audio, .video], sender: self);
            }));
        }
        #endif
        items.append(contentsOf: [
            UIAction(title: "Edit", image: UIImage(systemName: "pencil"), handler: {(action) in
                self.openEditItem(for: item.account, jid: item.jid);
            }),
            UIAction(title: "Info", image: UIImage(systemName: "info.circle"), handler: { action in
                self.showItemInfo(for: item.account, jid: item.jid);
            })
        ]);
        return UIMenu(title: "", children: items);
    }
    
    @IBAction func addBtnClicked(_ sender: UIBarButtonItem) {
        self.openEditItem(for: nil, jid: nil);
    }
    
    func deleteItem(for account: BareJID, jid: JID) {
        if let rosterModule:RosterModule = XmppService.instance.getClient(forJid: account)?.modulesManager.getModule(RosterModule.ID) {
            rosterModule.rosterStore.remove(jid: jid, onSuccess: nil, onError: { (errorCondition) in
                let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                self.present(alert, animated: true, completion: nil);
            })
        }
    }
    
    func openEditItem(for account: BareJID?, jid: JID?) {
        let navigationController = self.storyboard?.instantiateViewController(withIdentifier: "RosterItemEditNavigationController") as! UINavigationController;
        let itemEditController = navigationController.visibleViewController as? RosterItemEditViewController;
        itemEditController?.hidesBottomBarWhenPushed = true;
        itemEditController?.account = account;
        itemEditController?.jid = jid;
        navigationController.modalPresentationStyle = .formSheet;
        self.present(navigationController, animated: true, completion: nil);
    }
    
    func showItemInfo(for account: BareJID, jid: JID) {
        let navigation = storyboard?.instantiateViewController(withIdentifier: "ContactViewNavigationController") as! UINavigationController;
        let contactView = navigation.visibleViewController as! ContactViewController;
        contactView.hidesBottomBarWhenPushed = true;
        contactView.account = account;
        contactView.jid = jid.bareJid;
        navigation.title = self.navigationItem.title;
        navigation.modalPresentationStyle = .formSheet;
        self.present(navigation, animated: true, completion: nil);
    }
    
}

