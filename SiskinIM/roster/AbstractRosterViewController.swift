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
import Martin

class AbstractRosterViewController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate {
    
    var searchController: UISearchController!;
    
    var roster: RosterProvider?;
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchController = UISearchController(searchResultsController: nil);
        searchController.obscuresBackgroundDuringPresentation = false;
        searchController.hidesNavigationBarDuringPresentation = false;
        searchController.searchResultsUpdater = self;
        searchController.searchBar.searchBarStyle = .prominent;
        searchController.searchBar.isOpaque = false;
        searchController.searchBar.isTranslucent = true;
        refreshControl?.isOpaque = false;
        navigationItem.searchController = self.searchController;
        //tableView.rowHeight = 48;//UITableViewAutomaticDimension;
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
        initializeRosterProvider();
        super.viewWillAppear(animated);
    }
        
    func initializeRosterProvider() {
        self.roster?.release();
        switch Settings.rosterType {
        case .flat:
            roster = RosterProviderFlat(controller: self);
        case .grouped:
            roster = RosterProviderGrouped(controller: self);
        }
        self.tableView.reloadData();
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
            cell.statusLabel.text = item.account.stringValue;
            cell.avatarStatusView.displayableId = ContactManager.instance.contact(for: .init(account: item.account, jid: item.jid, type: .buddy));
        }
        
        return cell;
    }
        
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let v = view as? UITableViewHeaderFooterView {
            v.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline);
            v.textLabel?.text = v.textLabel?.text?.uppercased();
            v.textLabel?.textColor = UIColor.white;
            v.isOpaque = true;
            v.tintColor = UIColor(named: "chatslistBackground")?.lighter(ratio: 0.1);
        }
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        roster?.queryItems(contains: searchController.searchBar.text);
        tableView.reloadData();
    }
     
}


