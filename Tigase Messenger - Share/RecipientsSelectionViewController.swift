//
// RecipientsSelectionViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class RecipientsSelectionViewController: UITableViewController {
    
    var selected: [JID] = [];
    
    var allItems = [JID:RosterItem]();
    var items: [RosterItem] = [];
    
    var xmppClient: XMPPClient! {
        didSet {
            let store = RosterModule.getRosterStore(xmppClient.sessionObject) as! DefaultRosterStore;
            store.getJids().forEach({(jid) in
                if let item = store.get(for: jid) {
                    allItems[jid] = item;
                }
            });
            updateItem(item: nil);
        }
    }
    
    var delegate: ShareViewController?;
    
    var sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share");
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "recipientTableViewCell", for: indexPath) as! RecipientTableViewCell;
        let item = items[indexPath.row];
        cell.name.text = item.name ?? item.jid.stringValue;
        if selected.contains(item.jid) {
            cell.accessoryType = .checkmark;
        } else {
            cell.accessoryType = .none;
        }
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let jid = items[indexPath.row].jid;
        if let idx = selected.index(of: jid) {
            selected.remove(at: idx);
        } else {
            selected.append(jid);
        }
        delegate?.recipientsChanged(selected);
        tableView.reloadData();
    }
    
    func updateItem(item: RosterItem?) {
        if item != nil {
            allItems[item!.jid] = item!;
        }
        let showHidden = sharedDefaults!.bool(forKey: "RosterDisplayHiddenGroup");
        items = allItems.values.filter({ (ri) -> Bool in
            return showHidden || !ri.groups.contains("Hidden");
        }).sorted { (r1, r2) -> Bool in
            return (r1.name ?? r1.jid.stringValue).compare(r2.name ?? r2.jid.stringValue) == .orderedAscending;
        }
        tableView.reloadData();
    }
    
}
