//
// RosterProvider.swift
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
import TigaseSwift

protocol RosterProvider {
    
    var availableOnly: Bool { get set };

    var displayHiddenGroup: Bool { get set };
    
    var order: RosterSortingOrder { get set };
    
    func numberOfSections() -> Int;
    
    func numberOfRows(in section: Int) -> Int;
    
    func item(at indexPath: IndexPath) -> RosterProviderItem;
    
    func queryItems(contains: String?);
    
    func sectionHeader(at: Int) -> String?;
}

public enum RosterSortingOrder: String {
    case alphabetical
    case availability
}

public enum RosterType: String {
    case flat
    case grouped
}

public class RosterProviderAbstractBase {
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        DispatchQueue.main.async {
            self.handle(presenceEvent: e);
        }
    }
    
    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        DispatchQueue.main.async {
            self.handle(rosterItemUpdatedEvent: e);
        }
    }
    
    func handle(presenceEvent e: PresenceModule.ContactPresenceChanged) {
    }
    
    func handle(rosterItemUpdatedEvent e: RosterModule.ItemUpdatedEvent) {
    }
}

public class RosterProviderAbstract<Item: RosterProviderItem>: RosterProviderAbstractBase {
    
    let dbConnection:DBConnection;
    
    var availableOnly: Bool = false {
        didSet {
            if oldValue != availableOnly {
                _ = updateItems();
            }
        }
    }
    
    var displayHiddenGroup: Bool = false {
        didSet {
            if oldValue != displayHiddenGroup {
                _ = updateItems();
            }
        }
    }
    
    var order: RosterSortingOrder {
        didSet {
            if oldValue != order {
                _ = updateItems();
            }
        }
    }

    internal let updateNotificationName: Notification.Name;
    
    internal var allItems: [Item] = [];
    
    internal var queryString: String? = nil;
    
    init(dbConnection: DBConnection, order: RosterSortingOrder, availableOnly: Bool, displayHiddenGroup: Bool, updateNotificationName: Notification.Name) {
        self.dbConnection = dbConnection;
        self.order = order;
        self.updateNotificationName = updateNotificationName;
        self.availableOnly = availableOnly;
        self.displayHiddenGroup = displayHiddenGroup;
        super.init();
        self.allItems = self.loadItems();
        _ = updateItems();
    }
    
    func updateItems() -> Bool {
        return false;
    }
 
    func findItemFor(account: BareJID, jid: JID) -> Item? {
        if let idx = findItemIdxFor(account: account, jid: jid) {
            return allItems[idx];
        }
        return nil;
    }
    
    func findItemIdxFor(account: BareJID, jid: JID) -> Int? {
        let jidWithoutResource = JID(jid.bareJid);
        return allItems.firstIndex { (item) -> Bool in
            return item.account == account && (item.jid.resource != nil ? item.jid == jid : item.jid == jidWithoutResource)
        }
    }
    
    func notify(from: IndexPath? = nil, to: IndexPath? = nil) {
        guard from != nil || to != nil else {
            return;
        }
        
        notify(from: from != nil ? [from!] : nil, to: to != nil ? [to!] : nil);
    }
    
    func notify(from: [IndexPath]? = nil, to: [IndexPath]? = nil, refresh: Bool = false) {
        guard !refresh else {
            NotificationCenter.default.post(name: updateNotificationName, object: self, userInfo: ["refresh": refresh]);
            return;
        }
        guard from != nil || to != nil else {
            return;
        }
        guard !((from?.isEmpty ?? true) && (to?.isEmpty ?? true)) else {
            return;
        }
        
        NotificationCenter.default.post(name: updateNotificationName, object: self, userInfo: ["from": from as Any, "to": to as Any]);
    }
    
    func queryItems(contains: String?) {
        queryString = contains?.lowercased();
        if queryString != nil && queryString!.isEmpty {
            queryString = nil;
        }
        _ = updateItems();
    }
    
    func loadItems() -> [Item] {
        return try! self.dbConnection.prepareStatement("SELECT id, account, jid, name FROM roster_items")
            .query() { (it) in self.processDBloadQueryResult(it: it) };
    }
    
    func processDBloadQueryResult(it: DBCursor) -> Item? {
        return nil;
    }
    
}

public protocol RosterProviderItem {
    
    var account: BareJID { get }
    var jid: JID { get }
    var presence: Presence? { get }
    var displayName: String { get }

}


