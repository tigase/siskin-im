//
// AbstractRosterViewController.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class AbstractRosterViewController: CustomTableViewController, UISearchResultsUpdating, UISearchBarDelegate {
    
    fileprivate static let UPDATE_NOTIFICATION_NAME = Notification.Name("ROSTER_UPDATE");
    
    var xmppService:XmppService!;
    
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
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        super.viewDidLoad()
        searchController = UISearchController(searchResultsController: nil);
        searchController.dimsBackgroundDuringPresentation = false;
        searchController.searchResultsUpdater = self;
        searchController.searchBar.searchBarStyle = .prominent;
        
        Appearance.current.update(seachBar: self.searchController.searchBar);
        navigationItem.searchController = self.searchController;
        self.definesPresentationContext = true;
        tableView.rowHeight = 48;//UITableViewAutomaticDimension;
        self.navigationItem.hidesSearchBarWhenScrolling = true;
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
        initializeRosterProvider();
        reloadData();
        NotificationCenter.default.addObserver(self, selector: #selector(RosterViewController.reloadData), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
        Appearance.current.update(seachBar: searchController.searchBar);
    }
    
    func initializeRosterProvider(availableOnly: Bool = false, sortOrder: RosterSortingOrder = .alphabetical) {
        let rosterType = RosterType(rawValue: Settings.RosterType.getString() ?? "") ?? RosterType.flat;
        let displayHiddenGroup = Settings.RosterDisplayHiddenGroup.getBool();
        let dbConnection = (UIApplication.shared.delegate as! AppDelegate).dbConnection!;
        switch rosterType {
        case .flat:
            roster = RosterProviderFlat(xmppService: xmppService, dbConnection: dbConnection, order: sortOrder, availableOnly: availableOnly, displayHiddenGroup: displayHiddenGroup,  updateNotificationName: RosterViewController.UPDATE_NOTIFICATION_NAME);
        case .grouped:
            roster = RosterProviderGrouped(xmppService: xmppService, dbConnection: dbConnection, order: sortOrder, availableOnly: availableOnly, displayHiddenGroup: displayHiddenGroup, updateNotificationName: RosterViewController.UPDATE_NOTIFICATION_NAME);
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
        NotificationCenter.default.removeObserver(self);
        roster = nil;
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
        
        if let item = roster?.item(at: indexPath) {
            cell.nameLabel.text = item.displayName;
            cell.nameLabel.textColor = Appearance.current.labelColor;
            cell.statusLabel.textColor = Appearance.current.secondaryLabelColor;
            cell.statusLabel.text = item.account.stringValue;
            cell.avatarStatusView.setStatus(item.presence?.show);
            cell.avatarStatusView.backgroundColor = Appearance.current.systemBackground;
            cell.avatarStatusView.updateAvatar(manager: xmppService.avatarManager, for: item.account, with: item.jid.bareJid, name: item.displayName, orDefault: xmppService.avatarManager.defaultAvatar);
        }
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // nothing to do in this case
        cell.backgroundColor = Appearance.current.systemBackground;
    }
    
//    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
//        guard self.roster is RosterProviderGrouped else {
//            return nil;
//        }
//        guard let header = self.tableView(tableView, titleForHeaderInSection: section) else {
//            return nil;
//        }
//        let label = UILabel();
//        label.text = header;
//        return label;
//    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        super.tableView(tableView, willDisplayHeaderView: view, forSection: section);
        if let v = view as? UITableViewHeaderFooterView {
            v.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline);
            v.textLabel?.text = v.textLabel?.text?.uppercased();
            v.tintColor = Appearance.current.secondarySystemBackground;
            v.textLabel?.backgroundColor = Appearance.current.secondarySystemBackground;
        }
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        print("searching items containing:", searchController.searchBar.text ?? "");
        roster?.queryItems(contains: searchController.searchBar.text);
        tableView.reloadData();
    }

    func avatarChanged(_ notification: NSNotification) {
        DispatchQueue.main.async() {
            //            let jid = notification.userInfo!["jid"] as! BareJID;
            //            let indexPaths = self.indexPaths(for: jid);
            //            self.tableView.reloadRows(at: indexPaths, with: .automatic);
            self.tableView.reloadData();
        }
    }
    
    @objc func reloadData() {
        DispatchQueue.main.async() {
            self.tableView.reloadData();
        }
    }
    
    @objc func rowUpdated(_ notification: NSNotification) {
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
                let toAdd: [IndexPath] = Array(to![x..<to!.count]);
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


