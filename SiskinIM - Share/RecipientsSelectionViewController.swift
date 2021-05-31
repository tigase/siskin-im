//
// RecipientsSelectionViewController.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class RecipientsSelectionViewController: UITableViewController {
    
//    var selected: [JID] = [];
//
//    var allItems = [JID:RosterItem]();
//    var items: [RosterItem] = [];
//
//    var xmppClient: XMPPClient! {
//        didSet {
//            let store = RosterModule.getRosterStore(xmppClient.sessionObject) as! DefaultRosterStore;
//            self.allItems.removeAll();
//            store.getJids().forEach({(jid) in
//                if let item = store.get(for: jid) {
//                    allItems[jid] = item;
//                }
//            });
//            updateItem(item: nil);
//        }
//    }
    
    var delegate: ShareViewController?;
    
    var sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share");
    fileprivate let indicator = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 80, height: 80));
    
    override func viewDidLoad() {
        super.viewDidLoad();
        indicator.style = .gray;
        indicator.backgroundColor = UIColor.white;
        indicator.hidesWhenStopped = true;
        self.view.addSubview(indicator);
    }
    
//    override func viewWillAppear(_ animated: Bool) {
//        if xmppClient.state == .connecting {
//            indicator.startAnimating();
//        }
//        super.viewWillAppear(animated);
//        let view = self.parent!.view!;
//        indicator.center = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2);
//    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
//    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//        return items.count;
//    }
    
//    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//        let cell = tableView.dequeueReusableCell(withIdentifier: "recipientTableViewCell", for: indexPath) as! RecipientTableViewCell;
//        let item = items[indexPath.row];
//        cell.name.text = item.name ?? item.jid.stringValue;
//        if selected.contains(item.jid) {
//            cell.accessoryType = .checkmark;
//        } else {
//            cell.accessoryType = .none;
//        }
//        return cell;
//    }
    
//    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        let jid = items[indexPath.row].jid;
//        if let idx = selected.firstIndex(of: jid) {
//            selected.remove(at: idx);
//        } else {
//            selected.append(jid);
//        }
//        delegate?.recipientsChanged(selected);
//        tableView.reloadData();
//    }
    
    func hideIndicator() {
        DispatchQueue.main.async {
            if self.indicator.isAnimating {
                self.indicator.stopAnimating();
            }
        }
    }
    
//    func updateItem(item: RosterItem?) {
//        if item != nil {
//            allItems[item!.jid] = item!;
//        }
//        let showHidden = sharedDefaults!.bool(forKey: "RosterDisplayHiddenGroup");
//        let tmp: [RosterItem] = allItems.values.filter({ (ri) -> Bool in
//            return showHidden || !ri.groups.contains("Hidden");
//        });
//        items = tmp.sorted { (r1, r2) -> Bool in
//            return (r1.name ?? r1.jid.stringValue).compare(r2.name ?? r2.jid.stringValue) == .orderedAscending;
//        }
//        tableView.reloadData();
//        if item != nil {
//            hideIndicator();
//        }
//    }
    
}
