//
// RosterProviderFlat.swift
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

import Foundation
import Shared
import Martin
import Combine
import UIKit

public class RosterProviderFlat: RosterProviderAbstract<RosterProviderFlatItem>, RosterProvider {
    
    private var items: [RosterProviderFlatItem] = [];
    
    private var cancellables: Set<AnyCancellable> = [];
    
    private var initialized: Bool = false;
    
    override init(controller: AbstractRosterViewController) {
        self.items = [];
        super.init(controller: controller);
    }
    
    func numberOfSections() -> Int {
        return 1;
    }
    
    func numberOfRows(in section: Int) -> Int {
        return items.count;
    }
    
    func item(at indexPath: IndexPath) -> RosterProviderItem {
        return items[indexPath.row];
    }
    
    func sectionHeader(at: Int) -> String? {
        return nil;
    }
    
    override func newItem(rosterItem item: RosterItem, account: BareJID, presence: Presence?) -> RosterProviderFlatItem? {
        return RosterProviderFlatItem(account: account, jid: item.jid.bareJid, presence: presence, displayName: item.name ?? item.jid.stringValue);
    }
    
    override func updateItems(items: [RosterProviderFlatItem], order: RosterSortingOrder) {
        let oldItems = self.items;
        let newItems = sort(items: items, order: order);

        let diff = newItems.calculateChanges(from: oldItems);
        
        DispatchQueue.main.sync {
            self.items = newItems;
            if !initialized {
                initialized = true;
                self.controller?.tableView.reloadData();
            } else {
                self.controller?.tableView.beginUpdates();
                self.controller?.tableView.deleteRows(at: diff.removed.map({ IndexPath(row: $0, section: 0) }), with: .fade);
                self.controller?.tableView.insertRows(at: diff.inserted.map({ IndexPath(row: $0, section: 0) }), with: .fade);
                self.controller?.tableView.endUpdates();
            }
        }

    }
    
    func positionFor(item: RosterProviderItem) -> Int? {
        return items.firstIndex { $0.jid == item.jid && $0.account == item.account };
    }
}

public class RosterProviderFlatItem: RosterProviderItem, Hashable {
    
    public static func == (lhs: RosterProviderFlatItem, rhs: RosterProviderFlatItem) -> Bool {
        return lhs.account == rhs.account && lhs.jid == rhs.jid && lhs.displayName == rhs.displayName;
    }
    
    public let account: BareJID;
    public let jid: BareJID;
    public let presence: Presence?;
    public let displayName: String;
    
    init(account: BareJID, jid: BareJID, presence: Presence?, displayName: String) {
        self.account = account;
        self.jid = jid;
        self.presence = presence;
        self.displayName = displayName;
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(account);
        hasher.combine(jid);
    }
    
}
