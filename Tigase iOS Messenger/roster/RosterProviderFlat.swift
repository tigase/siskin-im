//
// RosterProviderFlat.swift
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

import Foundation
import TigaseSwift

public class RosterProviderFlat: RosterProviderAbstract<RosterProviderFlatItem>, RosterProvider {
    
    fileprivate var items: [RosterProviderFlatItem];
    
    override init(order: RosterSortingOrder, updateNotificationName: Notification.Name) {
        self.items = [];
        super.init(order: order, updateNotificationName: updateNotificationName);
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
    
    override func handle(presenceEvent e: PresenceModule.ContactPresenceChanged) {
        if let item = findItemFor(account: e.sessionObject.userBareJid!, jid: e.presence.from!) {
            let presence = PresenceModule.getPresenceStore(e.sessionObject).getBestPresence(for: e.presence.from!.bareJid);
            let changed = order != .alphabetical && item.presence?.show != presence?.show;
            item.update(presence: presence);
            let fromPos = positionFor(item: item);
            if changed {
                if updateItems() {
                    notify(refresh: true);
                    return;
                }
                let toPos = positionFor(item: item);
                notify(from: fromPos != nil ? IndexPath(row: fromPos!, section: 0) : nil, to: toPos != nil ? IndexPath(row: toPos!, section: 0) : nil);
            } else if fromPos != nil {
                let indexPath = IndexPath(row: fromPos!, section: 0);
                notify(from: indexPath, to: indexPath);
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
            let fromPos = positionFor(item: item);
            self.allItems.remove(at: idx!);
            if updateItems() {
                notify(refresh: true);
                return;
            }
            if fromPos != nil {
                notify(from: IndexPath(row: fromPos!, section: 0));
            }
        default:
            let item = idx != nil ? self.allItems[idx!] : RosterProviderFlatItem(account: e.sessionObject.userBareJid!, jid: e.rosterItem!.jid, name: e.rosterItem?.name, presence: nil);
            let fromPos = idx != nil ? positionFor(item: item) : nil;
            if idx != nil {
                item.name = e.rosterItem?.name;
            } else {
                self.allItems.append(item);
            }
            if updateItems() {
                notify(refresh: true);
                return;
            }
            let toPos = positionFor(item: item);
            notify(from: fromPos != nil ? IndexPath(row: fromPos!, section: 0) : nil, to: toPos != nil ? IndexPath(row: toPos!, section: 0) : nil);
        }
    }
    
    override func updateItems() -> Bool {
        var items = queryString == nil ? allItems : allItems.filter({ (item) -> Bool in
            if (item.name?.lowercased().contains(queryString!))! {
                return true;
            }
            if item.jid.stringValue.lowercased().contains(queryString!) {
                return true;
            }
            return false;
        });
        switch order {
        case .alphabetical:
            items.sort { (i1, i2) -> Bool in
                i1.displayName < i2.displayName;
            }
        case .availability:
            items.sort { (i1, i2) -> Bool in
                let s1 = i1.presence?.show?.weight ?? 0;
                let s2 = i2.presence?.show?.weight ?? 0;
                if s1 == s2 {
                    return i1.displayName < i2.displayName;
                }
                return s1 > s2;
            }
        }
        self.items = items;
        return false;
    }
    
    func positionFor(item: RosterProviderItem) -> Int? {
        return items.index { $0.jid == item.jid && $0.account == item.account };
    }
    
    
    override func processDBloadQueryResult(it: DBCursor) -> RosterProviderFlatItem? {
        let account: BareJID = it["account"]!;
        if let sessionObject = xmppService.getClient(forJid: account)?.sessionObject {
            let presenceStore = PresenceModule.getPresenceStore(sessionObject);
            let jid: JID = it["jid"]!;
            return RosterProviderFlatItem(account: account, jid: jid, name: it["name"], presence: presenceStore.getBestPresence(for: jid.bareJid));
        }
        return nil;
    }
}

public class RosterProviderFlatItem: RosterProviderItem {
    
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
    
    public init(account: BareJID, jid: JID, name:String?, presence: Presence?) {
        self.account = account;
        self.jid = jid;
        self.name = name;
        self.presence_ = presence;
    }
    
    fileprivate func update(presence: Presence?) {
        self.presence_ = presence;
    }
    
}
