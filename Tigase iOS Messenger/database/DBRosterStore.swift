//
// DBRosterStore.swift
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

public class DBRosterStoreWrapper: RosterStore {
    
    let sessionObject: SessionObject;
    let store:DBRosterStore;
    
    override public var count: Int {
        return store.count(sessionObject);
    }
    
    init(sessionObject: SessionObject, store: DBRosterStore) {
        self.sessionObject = sessionObject;
        self.store = store;
        super.init();
    }
    
    override public func addItem(item:RosterItem) {
        store.addItem(sessionObject, item: item);
    }
    
    override public func get(jid:JID) -> RosterItem? {
        return store.get(sessionObject, jid: jid);
    }
    
    override public func removeAll() {
        store.removeAll(sessionObject);
    }
    
    override public func removeItem(jid:JID) {
        store.removeItem(sessionObject, jid: jid);
    }
    
}

public class DBRosterStore: RosterCacheProvider {
    
    private let dbConnection: DBConnection;
    
    private lazy var addItemGroupStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INT")
    private lazy var countItemsStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM roster_items WHERE account = :account");
    private lazy var deleteItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items WHERE account = :account AND jid = :jid");
    private lazy var deleteItemGroupsStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items_groups WHERE item_id IN (SELECT id FROM roster_items WHERE account = :account AND jid = :jid)");
    private lazy var deleteItemsStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items WHERE account = :account");
    private lazy var deleteItemsGroupsStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items_groups WHERE item_id IN (SELECT id FROM roster_items WHERE account = :account)");
    
    private lazy var getGroupIdStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT id from roster_groups WHERE name = :name");
    private lazy var getItemGroupsStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT name FROM roster_groups rg INNER JOIN roster_items_groups rig ON rig.group_id = rg.id WHERE rig.item_id = :item_id");
    private lazy var getItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT id, name, subscription, ask FROM roster_items WHERE account = :account AND jid = :jid");
    
    private lazy var insertGroupStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO roster_groups (name) VALUES (:name)");
    private lazy var insertItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO roster_items (account, jid, name, subscription, timestamp, ask) VALUES (:account, :jid, :name, :subscription, :timestamp, :ask)");
    private lazy var insertItemGroupStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO roster_items_groups (item_id, group_id) VALUES (:item_id, :group_id)");
    private lazy var updateItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("UPDATE roster_items SET name = :name, subscription = :subscription, timestamp = :timestamp, ask = :ask WHERE account = :account AND jid = :jid");
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    public func count(sessionObject: SessionObject) -> Int {
        do {
            let params:[String:Any?] = ["account" : sessionObject.userBareJid!.stringValue];
            return try countItemsStmt.scalar(params) ?? 0;
        } catch _ {
            
        }
        return 0;
    }
    
    public func addItem(sessionObject: SessionObject, item:RosterItem) {
        do {
            let params:[String:Any?] = [ "account": sessionObject.userBareJid?.stringValue, "jid": item.jid.stringValue, "name": item.name, "subscription": String(item.subscription.rawValue), "timestamp": NSDate(), "ask": item.ask ];
            var dbItem = item as? DBRosterItem ?? DBRosterItem(rosterItem: item);
            if dbItem.id == nil {
                // adding roster item to DB
                dbItem.id = try insertItemStmt.insert(params);
            } else {
                // updating roster item in DB
                try updateItemStmt.execute(params);
                let itemGroupsDeleteParams:[String:Any?] = ["account": sessionObject.userBareJid?.stringValue, "jid": dbItem.jid.stringValue];
                try deleteItemGroupsStmt.execute(itemGroupsDeleteParams);
            }
            
            for group in dbItem.groups {
                var groupId = try? getGroupIdStmt.scalar(["name": group]);
                if groupId == nil {
                    groupId = try? insertGroupStmt.insert(["name": group]);
                }
                try insertItemGroupStmt.insert(["item_id": item.id, "group_id": groupId]);
            }
        } catch _ {
            
        }
    }
    
    public func get(sessionObject: SessionObject, jid:JID) -> RosterItem? {
        var item:DBRosterItem? = nil;
        do {
            let params:[String:Any?] = [ "account" : sessionObject.userBareJid?.stringValue, "jid" : jid.stringValue ];
            try getItemStmt.query(params) { cursor -> Void in
                item = DBRosterItem(jid: jid, id: cursor["id"]!);
                item?.name = cursor["name"];
                item?.subscription = RosterItem.Subscription(rawValue: cursor["subscription"]!)!;
                item?.ask = cursor["ask"]!;
            }
            try getItemGroupsStmt.query(["item_id": item?.id]) { cursor -> Void in
                item?.groups.append(cursor["name"]!);
            }
        } catch _ {
            
        }
        return item;
    }
    
    public func removeAll(sessionObject: SessionObject) {
        let params:[String:Any?] = ["account": sessionObject.userBareJid?.stringValue];
        do {
            try deleteItemsGroupsStmt.execute(params);
            try deleteItemsStmt.execute(params);
        } catch _ {
            
        }
    }
    
    public func removeItem(sessionObject: SessionObject, jid:JID) {
        do {
            let params:[String:Any?] = ["account": sessionObject.userBareJid?.stringValue, "jid": jid.stringValue];
            try deleteItemGroupsStmt.execute(params);
            try deleteItemStmt.execute(params);
        } catch _ {
            
        }
    }
    
    public func getCachedVersion(sessionObject: SessionObject) -> String? {
        return AccountManager.getAccount(sessionObject.userBareJid!.stringValue)?.rosterVersion;
    }
    
    public func loadCachedRoster(sessionObject: SessionObject) -> [RosterItem] {
        return [RosterItem]();
    }
    
    public func updateReceivedVersion(sessionObject: SessionObject, ver: String?) {
        if let account = AccountManager.getAccount(sessionObject.userBareJid!.stringValue) {
            account.rosterVersion = ver;
            AccountManager.updateAccount(account, notifyChange: false);
        }
    }
}

extension RosterItemProtocol {
    var id:Int? {
        switch self {
        case let ri as DBRosterItem:
            return ri.id;
        default:
            return nil;
        }
    }
}

class DBRosterItem: RosterItem {
    var id:Int? = nil;
    
    init(jid: JID, id: Int) {
        self.id = id;
        super.init(jid: jid);
    }
    
    init(rosterItem item: RosterItem) {
        super.init(jid: item.jid);
        self.name = item.name;
        self.subscription = item.subscription;
        self.ask = item.ask;
        self.groups = item.groups;
    }
}

