//
//  RosterProviderGrouped.swift
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

public class RosterProviderGrouped: RosterProviderAbstract<RosterProviderGroupedItem>, RosterProvider {
    
    fileprivate var items: [String: [RosterProviderGroupedItem]];
    
    var groups = [String]();
    
    override init(order: RosterSortingOrder, availableOnly: Bool, updateNotificationName: Notification.Name) {
        self.items = [:];
        super.init(order: order, availableOnly: availableOnly, updateNotificationName: updateNotificationName);
    }
    
    func numberOfSections() -> Int {
        return groups.count;
    }
    
    func numberOfRows(in section: Int) -> Int {
        let group = groups[section];
        return items[group]!.count;
    }
    
    func item(at indexPath: IndexPath) -> RosterProviderItem {
        let group = groups[indexPath.section];
        return items[group]![indexPath.row];
    }
    
    func sectionHeader(at: Int) -> String? {
        return groups[at];
    }
    
    override func handle(presenceEvent e: PresenceModule.ContactPresenceChanged) {
        if let item = findItemFor(account: e.sessionObject.userBareJid!, jid: e.presence.from!) {
            let presence = PresenceModule.getPresenceStore(e.sessionObject).getBestPresence(for: e.presence.from!.bareJid);
            let changed = order != .alphabetical && item.presence?.show != presence?.show;
            item.update(presence: presence);

            let fromPos = positionsFor(item: item);
            if changed {
                if updateItems() {
                    notify(refresh: true);
                    return;
                }
                let toPos = positionsFor(item: item);
                notify(from: fromPos, to: toPos);
            } else {
                notify(from: fromPos, to: fromPos);
            }
        }
    }
    
    override func handle(rosterItemUpdatedEvent e: RosterModule.ItemUpdatedEvent) {
        let cleared = e.rosterItem == nil;
        guard !cleared else {
            return;
        }
        let idx = findItemIdxFor(account: e.sessionObject.userBareJid!, jid: e.rosterItem!.jid)
        switch e.action! {
        case .removed:
            guard idx != nil else {
                return;
            }
            let item = self.allItems[idx!];
            let fromPos = positionsFor(item: item);
            self.allItems.remove(at: idx!);
            if updateItems() {
                notify(refresh: true);
                return;
            }
            if !fromPos.isEmpty {
                notify(from: fromPos);
            }
        default:
            let item = idx != nil ? self.allItems[idx!] : RosterProviderGroupedItem(account: e.sessionObject.userBareJid!, jid: e.rosterItem!.jid, name: e.rosterItem?.name, presence: nil);
            let fromPos = positionsFor(item: item);

            item.groups = e.rosterItem!.groups;
            
            if idx != nil {
                item.name = e.rosterItem?.name;
            } else {
                self.allItems.append(item);
            }
            if updateItems() {
                notify(refresh: true);
                return;
            }

            let toPos = positionsFor(item: item);
            notify(from: fromPos, to: toPos);
        }
    }
    
    override func updateItems() -> Bool {
        var groups: Set<String> = [];
        let items = queryString == nil ? (!availableOnly ? allItems : allItems.filter { (item) -> Bool in item.presence?.show != nil }) : allItems.filter({ (item) -> Bool in
            if (item.name?.lowercased().contains(queryString!))! {
                return true;
            }
            if item.jid.stringValue.lowercased().contains(queryString!) {
                return true;
            }
            return false;
        });
        var groupedItems: [String:[RosterProviderGroupedItem]] = [:];
        items.forEach { item in
            groups = groups.union(item.groups)
            item.groups.forEach { group in
                var groupItems = groupedItems[group] ?? [];
                groupItems.append(item);
                groupedItems[group] = groupItems;
            }
        }
        
        let oldGroups = self.groups;
        let needToAddDefault = groups.remove("Default") != nil;
        self.groups = groups.sorted();
        if needToAddDefault {
            self.groups.insert("Default", at: 0);
        }
        
        self.groups.forEach { group in
            var groupItems = groupedItems[group]!;
            switch order {
            case .alphabetical:
                groupItems.sort { (i1, i2) -> Bool in
                    i1.displayName < i2.displayName;
                }
            case .availability:
                groupItems.sort { (i1, i2) -> Bool in
                    let s1 = i1.presence?.show?.weight ?? 0;
                    let s2 = i2.presence?.show?.weight ?? 0;
                    if s1 == s2 {
                        return i1.displayName < i2.displayName;
                    }
                    return s1 > s2;
                }
            }
            groupedItems[group] = groupItems;
        }
        
        self.items = groupedItems;
        
        return oldGroups == self.groups;
    }
    
    func positionsFor(item: RosterProviderGroupedItem) -> [IndexPath] {
        var paths = [IndexPath]();
        
        item.groups.forEach { group in
            if let idx = self.items[group]?.index(where: { $0.jid == item.jid && $0.account == item.account }) {
                let gidx = groups.index(of: group);
                paths.append(IndexPath(row: idx, section: gidx!));
            }
        }
        
        return paths;
    }
    
    override func loadItems() -> [RosterProviderGroupedItem] {
        let items = super.loadItems();
        
        var tmp: [BareJID:[JID: [String]]] = [:];
        try! self.dbConnection.prepareStatement("SELECT ri.account, ri.jid, rg.name AS group_name FROM roster_items ri INNER JOIN roster_items_groups rig ON ri.id = rig.item_id INNER JOIN roster_groups rg ON rg.id = rig.group_id").query() { (it) -> Void in
            let account: BareJID = it["account"]!;
            let jid: JID = it["jid"]!;
            let group: String = it["group_name"]!;
            
            var jids = tmp[account] ?? [:];
            var groups: [String]? = jids[jid];
            
            if groups == nil {
                jids[jid] = [group];
            } else {
                groups!.append(group);
                jids[jid] = groups;
            }
            
            tmp[account] = jids;
        }
        
        items.forEach { (item) in
            if let groups = tmp[item.account]?[item.jid] {
                item.groups = groups;
            }
        }
        
        return items;
    }
    
    override func processDBloadQueryResult(it: DBCursor) -> RosterProviderGroupedItem? {
        let account: BareJID = it["account"]!;
        if let sessionObject = xmppService.getClient(forJid: account)?.sessionObject {
            let presenceStore = PresenceModule.getPresenceStore(sessionObject);
            let jid: JID = it["jid"]!;
            return RosterProviderGroupedItem(account: account, jid: jid, name: it["name"], presence: presenceStore.getBestPresence(for: jid.bareJid));
        }
        return nil;
    }
}

public class RosterProviderGroupedItem: RosterProviderItem {
    
    public let account: BareJID;
    internal var name: String?;
    public let jid: JID;
    fileprivate var presence_: Presence?;
    public var presence: Presence? {
        return presence_;
    }
    
    public var displayName: String {
        return name != nil ? name! : jid.stringValue;
    }
    
    fileprivate var groups: [String] {
        didSet {
            if groups.isEmpty {
                groups = ["Default"];
            }
        }
    }
    
    public init(account: BareJID, jid: JID, name:String?, presence: Presence?) {
        self.account = account;
        self.jid = jid;
        self.name = name;
        self.presence_ = presence;
        self.groups = ["Default"];
    }
    
    fileprivate func update(presence: Presence?) {
        self.presence_ = presence;
    }
    
}
