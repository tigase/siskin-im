//
// RosterProviderGrouped.swift
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
import Shared
import Martin

public class RosterProviderGrouped: RosterProviderAbstract<RosterProviderGroupedItem>, RosterProvider {
    
    private var groups = [RosterProviderGroup]();
    
    private var initialized = false;
    
    override init(controller: AbstractRosterViewController) {
        super.init(controller: controller);
    }
    
    func numberOfSections() -> Int {
        return groups.count;
    }
    
    func numberOfRows(in section: Int) -> Int {
        return groups[section].items.count;
    }
    
    func item(at indexPath: IndexPath) -> RosterProviderItem {
        return groups[indexPath.section].items[indexPath.row];
    }
    
    func sectionHeader(at: Int) -> String? {
        return groups[at].name;
    }
    
    override func newItem(rosterItem item: RosterItem, account: BareJID, presence: Presence?) -> RosterProviderGroupedItem? {
        let groups = item.groups.isEmpty ? [NSLocalizedString("Default ", comment: "default roster group")] : item.groups;
        return RosterProviderGroupedItem(account: account, jid: item.jid.bareJid, presence: presence, displayName: item.name ?? item.jid.stringValue, groups: groups);
    }
    
    override func updateItems(items: [RosterProviderGroupedItem], order: RosterSortingOrder) {
        let groupNames = Set(items.flatMap({ $0.groups })).sorted();
        let newGroups = groupNames.map({ name in RosterProviderGroup(name: name, items: self.sort(items: items.filter({ $0.groups.contains(name) }), order: order))});
        let oldGroups = self.groups;

        let removeSections = IndexSet(oldGroups.map({ $0.name }).filter({ !groupNames.contains($0) }).compactMap({ name in oldGroups.firstIndex(where: { $0.name == name })}));
        let newSections = IndexSet(newGroups.map({ $0.name }).filter({ name in !oldGroups.contains(where: { $0.name == name })}).compactMap({ name in newGroups.firstIndex(where: { $0.name == name }) }));
        
        let rowChanges = calculateChanges(newGroups: newGroups, oldGroups: oldGroups);
        
        DispatchQueue.main.sync {
            self.groups = newGroups;
            if !self.initialized {
                self.initialized = true;
                self.controller?.tableView.reloadData();
            } else {
                self.controller?.tableView.beginUpdates();
                self.controller?.tableView.deleteSections(removeSections, with: .fade);
                for changes in rowChanges {
                    self.controller?.tableView.deleteRows(at: changes.removed, with: .fade);
                    self.controller?.tableView.insertRows(at: changes.inserted, with: .fade);
                }
                self.controller?.tableView.insertSections(newSections, with: .fade);
                self.controller?.tableView.endUpdates();
            }
        }
    }
    
    struct GroupChanges {
        let inserted: [IndexPath];
        let removed: [IndexPath];
    }
    
    private func calculateChanges(newGroups: [RosterProviderGroup], oldGroups: [RosterProviderGroup]) -> [GroupChanges] {
        var results: [GroupChanges] = [];
        for newGroup in newGroups {
            if let oldGroup = oldGroups.first(where: { $0.name == newGroup.name }) {
                let diff = newGroup.items.calculateChanges(from: oldGroup.items);
                results.append(GroupChanges(inserted: diff.inserted.map({ [results.count, $0] }), removed: diff.removed.map({ [results.count, $0] })));
            }
        }
        return results;
    }
    
    func positionsFor(item: RosterProviderGroupedItem) -> [IndexPath] {
        var paths = [IndexPath]();
        
        for section in 0..<groups.count {
            if let row = groups[section].items.firstIndex(where: { $0.jid == item.jid && $0.account == item.account }) {
                paths.append(IndexPath(row: row, section: section));
            }
        }
        
        return paths;
    }
    
}

public class RosterProviderGroup {
    
    public let name: String;
    public let items: [RosterProviderGroupedItem];
    
    init(name: String, items: [RosterProviderGroupedItem]) {
        self.name = name;
        self.items = items;
    }
    
}

public class RosterProviderGroupedItem: RosterProviderItem, Hashable {
    
    public static func == (lhs: RosterProviderGroupedItem, rhs: RosterProviderGroupedItem) -> Bool {
        return lhs.account == rhs.account && lhs.jid == rhs.jid && lhs.displayName == rhs.displayName;
    }
    
    public let account: BareJID;
    public let jid: BareJID;
    public let presence: Presence?;
    public let displayName: String;
    public let groups: [String];
    
    init(account: BareJID, jid: BareJID, presence: Presence?, displayName: String, groups: [String]) {
        self.account = account;
        self.jid = jid;
        self.presence = presence;
        self.displayName = displayName;
        self.groups = groups;
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(account);
        hasher.combine(jid);
    }

}
