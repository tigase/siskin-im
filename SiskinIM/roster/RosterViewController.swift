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

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchBar.delegate = self;
        searchController.searchBar.scopeButtonTitles = ["By name", "By status"];
        
        // Do any additional setup after loading the view, typically from a nib.
        let lpgr = UILongPressGestureRecognizer(target: self, action: #selector(RosterViewController.handleLongPress));
        lpgr.minimumPressDuration = 1.0;
        lpgr.delegate = self;
        tableView.addGestureRecognizer(lpgr);

        navigationItem.leftBarButtonItem = self.editButtonItem
        let availabilityFilterSelector = UISegmentedControl(items: ["All", "Available"]);
        navigationItem.titleView = availabilityFilterSelector;
        availabilityFilterSelector.selectedSegmentIndex = Settings.RosterAvailableOnly.getBool() ? 1 : 0;
        availabilityFilterSelector.addTarget(self, action: #selector(RosterViewController.availabilityFilterChanged), for: .valueChanged);
        
    }
    
    override func initializeRosterProvider(availableOnly: Bool, sortOrder: RosterSortingOrder) {
        super.initializeRosterProvider(availableOnly: Settings.RosterAvailableOnly.getBool(), sortOrder: RosterSortingOrder(rawValue: Settings.RosterItemsOrder.getString() ?? "") ?? .alphabetical);
        
        switch roster.order {
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
            cell.nameLabel.textColor = Appearance.current.labelColor;
            cell.statusLabel.textColor = Appearance.current.secondaryLabelColor;
            cell.statusLabel.text = item.presence?.status ?? item.jid.stringValue;
            cell.avatarStatusView.setStatus(item.presence?.show);
            cell.avatarStatusView.backgroundColor = Appearance.current.systemBackground;
            cell.avatarStatusView.set(name: item.displayName, avatar: AvatarManager.instance.avatar(for: item.jid.bareJid, on: item.account), orDefault: AvatarManager.instance.defaultAvatar);
        }
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = roster?.item(at: indexPath) else {
            return;
        }

        let xmppClient = XmppService.instance.getClient(forJid: item.account);
        let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
        
        guard messageModule != nil else {
            return;
        }
        
        _ = messageModule!.chatManager!.getChatOrCreate(with: item.jid, thread: nil);
        
        let destination = self.storyboard!.instantiateViewController(withIdentifier: "ChatViewNavigationController") as! UINavigationController;
        let chatController = destination.children[0] as! ChatViewController;
        chatController.hidesBottomBarWhenPushed = true;
        chatController.account = item.account;
        chatController.jid = item.jid.bareJid;
        self.showDetailViewController(destination, sender: self);
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = roster.item(at: indexPath);
            let account: BareJID = item.account;
            let jid: JID = item.jid;
            self.deleteItem(for: account, jid: jid);
        }
    }
    
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [UITableViewRowAction(style: .destructive, title: "Delete", handler: {(action, path) in
            print("deleting record at", path);
            let item = self.roster.item(at: indexPath);
            self.deleteItem(for: item.account, jid: item.jid);
        }),UITableViewRowAction(style: .normal, title: "Edit", handler: {(action, path) in
            print("editing record at ", path);
            let item = self.roster.item(at: indexPath);
            self.openEditItem(for: item.account, jid: item.jid);
        })];
    }
    
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        roster.order = selectedScope == 0 ? .alphabetical : .availability
        Settings.RosterItemsOrder.setValue(roster.order.rawValue);
        tableView.reloadData();
    }
    
    @objc func availabilityFilterChanged(_ control: UISegmentedControl) {
        roster.availableOnly = control.selectedSegmentIndex == 1;
        Settings.RosterAvailableOnly.setValue(roster.availableOnly);
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

            let item = roster.item(at: indexPath);
            
            let alert = UIAlertController(title: item.displayName, message: "using \(item.account.stringValue)", preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Chat", style: .default, handler: { (action) in
                self.tableView(self.tableView, didSelectRowAt: indexPath);
            }));
            #if targetEnvironment(simulator)
            #else
            let jingleSupport = JingleManager.instance.support(for: item.jid, on: item.account);
            if jingleSupport.contains(.audio) && jingleSupport.contains(.video) {
                alert.addAction(UIAlertAction(title: "Video call", style: .default, handler: { (action) in
                    VideoCallController.call(jid: item.jid.bareJid, from: item.account, withAudio: true, withVideo: true, sender: self);
                }));
            }
            if jingleSupport.contains(.audio) {
                alert.addAction(UIAlertAction(title: "Audio call", style: .default, handler: { (action) in
                    VideoCallController.call(jid: item.jid.bareJid, from: item.account, withAudio: true, withVideo: false, sender: self);
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

