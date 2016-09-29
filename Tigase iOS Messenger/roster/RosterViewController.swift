//
// RosterViewController.swift
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

class RosterViewController: UITableViewController, UIGestureRecognizerDelegate, UISearchResultsUpdating, UISearchBarDelegate {

    fileprivate static let UPDATE_NOTIFICATION_NAME = Notification.Name("ROSTER_UPDATE");
        
    var xmppService:XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    var searchController: UISearchController!;
    
    var roster: RosterProvider! {
        didSet {
            if oldValue != nil {
                xmppService.unregisterEventHandler(oldValue!, for: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
            }
            if roster != nil {
                xmppService.registerEventHandler(roster!, for: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
            }
        }
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
        searchController = UISearchController(searchResultsController: nil);
        searchController.dimsBackgroundDuringPresentation = false;
        searchController.searchResultsUpdater = self;
        searchController.searchBar.delegate = self;
        searchController.searchBar.scopeButtonTitles = ["By name", "By status"];
        tableView.tableHeaderView = self.searchController.searchBar;
        self.definesPresentationContext = true;
        tableView.rowHeight = 48;//UITableViewAutomaticDimension;
        //tableView.estimatedRowHeight = 48;
        // Do any additional setup after loading the view, typically from a nib.
        let lpgr = UILongPressGestureRecognizer(target: self, action: #selector(RosterViewController.handleLongPress));
        lpgr.minimumPressDuration = 2.0;
        lpgr.delegate = self;
        tableView.addGestureRecognizer(lpgr);
        navigationItem.leftBarButtonItem = self.editButtonItem
        let availabilityFilterSelector = UISegmentedControl(items: ["All", "Available"]);
        navigationItem.titleView = availabilityFilterSelector;
        availabilityFilterSelector.selectedSegmentIndex = Settings.RosterAvailableOnly.getBool() ? 1 : 0;
        availabilityFilterSelector.addTarget(self, action: #selector(RosterViewController.availabilityFilterChanged), for: .valueChanged);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
        if !self.isBeingPresented {
            roster = nil;
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(RosterViewController.rowUpdated), name: RosterViewController.UPDATE_NOTIFICATION_NAME, object: nil);
        let sortOrder = RosterSortingOrder(rawValue: Settings.RosterItemsOrder.getString() ?? "") ?? .alphabetical;
        let rosterType = RosterType(rawValue: Settings.RosterType.getString() ?? "") ?? RosterType.flat;
        let availableOnly = Settings.RosterAvailableOnly.getBool();
        switch rosterType {
        case .flat:
            roster = RosterProviderFlat(order: sortOrder, availableOnly: availableOnly, updateNotificationName: RosterViewController.UPDATE_NOTIFICATION_NAME);
        case .grouped:
            roster = RosterProviderGrouped(order: sortOrder, availableOnly: availableOnly, updateNotificationName: RosterViewController.UPDATE_NOTIFICATION_NAME);
        }
        switch roster.order {
            case .alphabetical:
                searchController.searchBar.selectedScopeButtonIndex = 0;
            case .availability:
                searchController.searchBar.selectedScopeButtonIndex = 1;
        }
        reloadData();
        NotificationCenter.default.addObserver(self, selector: #selector(RosterViewController.reloadData), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
        NotificationCenter.default.removeObserver(self);
    }

    override func numberOfSections(in: UITableView) -> Int {
        return roster?.numberOfSections() ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return roster?.numberOfRows(in: section) ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return roster?.sectionHeader(at: section);
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "RosterItemTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! RosterItemTableViewCell;
        
        let item = roster.item(at: indexPath);
        
        cell.nameLabel.text = item.displayName;
        cell.statusLabel.text = item.presence?.status ?? item.jid.stringValue;
        cell.avatarStatusView.setStatus(item.presence?.show);
        cell.avatarStatusView.setAvatar(xmppService.avatarManager.getAvatar(for: item.jid.bareJid, account: item.account));
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = roster.item(at: indexPath);

        let xmppClient = self.xmppService.getClient(forJid: item.account);
        let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
        
        guard messageModule != nil else {
            return;
        }
        
        if !self.xmppService.dbChatStore.isFor(xmppClient!.sessionObject, jid: item.jid.bareJid) {
            _ = messageModule!.createChat(with: item.jid);
        }
        
        let destination = self.storyboard!.instantiateViewController(withIdentifier: "ChatViewNavigationController") as! UINavigationController;
        let chatController = destination.childViewControllers[0] as! ChatViewController;
        chatController.hidesBottomBarWhenPushed = true;
        chatController.account = item.account;
        chatController.jid = item.jid;
        self.showDetailViewController(destination, sender: self);
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = roster.item(at: indexPath);
            let account: BareJID = item.account;
            let jid: JID = item.jid;
            if let rosterModule:RosterModule = self.xmppService.getClient(forJid: account)?.modulesManager.getModule(RosterModule.ID) {
                rosterModule.rosterStore.remove(jid: jid, onSuccess: nil, onError: { (errorCondition) in
                    let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                    self.present(alert, animated: true, completion: nil);
                })
            }
        }
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        print("searching items containing:", searchController.searchBar.text);
        roster?.queryItems(contains: searchController.searchBar.text);
        tableView.reloadData();
    }
    
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        roster.order = selectedScope == 0 ? .alphabetical : .availability
        Settings.RosterItemsOrder.setValue(roster.order.rawValue);
        tableView.reloadData();
    }
    
    func availabilityFilterChanged(_ control: UISegmentedControl) {
        roster.availableOnly = control.selectedSegmentIndex == 1;
        Settings.RosterAvailableOnly.setValue(roster.availableOnly);
        tableView.reloadData();
    }
    
    func handleLongPress(_ gestureRecognizer:UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else {
            return
        }

        let point = gestureRecognizer.location(in: self.tableView);
        if let indexPath = self.tableView.indexPathForRow(at: point) {
            print("long press detected at", indexPath);

            let item = roster.item(at: indexPath);
            self.openEditItem(for: item.account, jid: item.jid);
        }
    }
    
    
    @IBAction func addBtnClicked(_ sender: UIBarButtonItem) {
        self.openEditItem(for: nil, jid: nil);
    }
    
    func openEditItem(for account: BareJID?, jid: JID?) {
        let navigationController = self.storyboard?.instantiateViewController(withIdentifier: "RosterItemEditNavigationController") as! UINavigationController;
        let itemEditController = navigationController.visibleViewController as? RosterItemEditViewController;
        itemEditController?.account = account;
        itemEditController?.jid = jid;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    func avatarChanged(_ notification: NSNotification) {
        DispatchQueue.main.async() {
//            let jid = notification.userInfo!["jid"] as! BareJID;
//            let indexPaths = self.indexPaths(for: jid);
//            self.tableView.reloadRows(at: indexPaths, with: .automatic);
            self.tableView.reloadData();
        }
    }
    
    func reloadData() {
        DispatchQueue.main.async() {
            self.tableView.reloadData();
        }
    }

    func rowUpdated(_ notification: NSNotification) {
        guard let info = notification.userInfo else {
            return;
        }
        
        guard !(info["refresh"] as? Bool ?? false) else {
            self.tableView.reloadData();
            return;
        }
        
        let from = info["from"] as? [IndexPath];
        let to = info["to"] as? [IndexPath];
        
        if to == nil {
            self.tableView.deleteRows(at: from!, with: .automatic);
            return;
        }
        if from == nil {
            self.tableView.insertRows(at: to!, with: .automatic);
            return;
        }
        if from! == to! {
            self.tableView.reloadRows(at: from!, with: .automatic);
        } else {
            self.tableView.beginUpdates();
            let x = min(from!.count, to!.count)
            if x < from!.count {
                let toDelete: [IndexPath] = Array(from![x..<from!.count]);
                self.tableView.deleteRows(at: toDelete, with: .automatic);
            }
            if x < to!.count {
                let toAdd: [IndexPath] = Array(from![x..<from!.count]);
                self.tableView.insertRows(at: toAdd, with: .automatic);
            }
            for i in 0..<x {
                self.tableView.moveRow(at: from![i], to: to![i]);
            }
            self.tableView.endUpdates();
            self.tableView.reloadRows(at: to!, with: .automatic);
        }
    }
    
}

