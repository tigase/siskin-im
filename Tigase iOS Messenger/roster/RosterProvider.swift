//
// RosterProvider.swift
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

protocol RosterProvider: EventHandler {
    
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

public class RosterProviderAbstract<Item: RosterProviderItem> {
    
    let dbConnection:DBConnection;
    
    let xmppService: XmppService;
    
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
    
    init(xmppService: XmppService, dbConnection: DBConnection, order: RosterSortingOrder, availableOnly: Bool, displayHiddenGroup: Bool, updateNotificationName: Notification.Name) {
        self.xmppService = xmppService;
        self.dbConnection = dbConnection;
        self.order = order;
        self.updateNotificationName = updateNotificationName;
        self.availableOnly = availableOnly;
        self.displayHiddenGroup = displayHiddenGroup;
        self.allItems = self.loadItems();
        _ = updateItems();
    }
    
    public func handle(event: Event) {
        DispatchQueue.main.async {
            switch(event) {
            case let e as PresenceModule.ContactPresenceChanged:
                self.handle(presenceEvent: e);
            case let e as RosterModule.ItemUpdatedEvent:
                self.handle(rosterItemUpdatedEvent: e);
            default:
                break;
            }
        }
    }
    
    func handle(presenceEvent e: PresenceModule.ContactPresenceChanged) {
    }
    
    func handle(rosterItemUpdatedEvent e: RosterModule.ItemUpdatedEvent) {
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
        return allItems.index { (item) -> Bool in
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
        
        NotificationCenter.default.post(name: updateNotificationName, object: self, userInfo: ["from": from, "to": to]);
    }
    
    func queryItems(contains: String?) {
        queryString = contains?.lowercased();
        if queryString != nil && queryString!.isEmpty {
            queryString = nil;
        }
        _ = updateItems();
    }
    
    func loadItems() -> [Item] {
        var items = [Item]();
        try! self.dbConnection.prepareStatement("SELECT id, account, jid, name FROM roster_items").query(forEachRow: { (it) -> Void in
            let item = self.processDBloadQueryResult(it: it);
            if item != nil {
                items.append(item!);
            }
        });
        return items;
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


