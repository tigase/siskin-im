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
    
    let cache: NSCache?;
    
    let sessionObject: SessionObject;
    let store:DBRosterStore;
    
    override public var count: Int {
        return store.count(sessionObject);
    }
    
    init(sessionObject: SessionObject, store: DBRosterStore, useCache: Bool = true) {
        self.sessionObject = sessionObject;
        self.store = store;
        self.cache = useCache ? NSCache() : nil;
        self.cache?.countLimit = 100;
        self.cache?.totalCostLimit = 1 * 1024 * 1024;
        super.init();
    }
    
    override public func addItem(item:RosterItem) {
        store.addItem(sessionObject, item: item);
        cache?.setObject(item, forKey: item.jid.stringValue);
    }
    
    override public func get(jid:JID) -> RosterItem? {
        if let item = cache?.objectForKey(jid.stringValue) as? RosterItem {
            return item;
        }
        if let item = store.get(sessionObject, jid: jid) {
            cache?.setObject(item, forKey: jid.stringValue);
            return item;
        }
        return nil;
    }
    
    override public func removeAll() {
        cache?.removeAllObjects();
        store.removeAll(sessionObject);
    }
    
    override public func removeItem(jid:JID) {
        cache?.removeObjectForKey(jid.stringValue);
        store.removeItem(sessionObject, jid: jid);
    }
    
}

public class DBRosterStore: RosterCacheProvider, LocalQueueDispatcher {
    
    private let dbConnection: DBConnection;
    
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
    
    public var queue: dispatch_queue_t = dispatch_queue_create("db_roster_store_queue", DISPATCH_QUEUE_SERIAL);
    public var queueTag: UnsafeMutablePointer<Void>;
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        self.queueTag = UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self.queue).toOpaque());
        dispatch_queue_set_specific(queue, queueTag, queueTag, nil);

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(DBRosterStore.accountRemoved), name: "accountRemoved", object: nil);
    }
    
    public func count(sessionObject: SessionObject) -> Int {
        do {
            let params:[String:Any?] = ["account" : sessionObject.userBareJid!.stringValue];
            return try countItemsStmt.scalar(params) ?? 0;
        } catch _ {
            
        }
        return 0;
    }
    
    public func addItem(sessionObject: SessionObject, item:RosterItem) -> RosterItem? {
        do {
            let params:[String:Any?] = [ "account": sessionObject.userBareJid, "jid": item.jid, "name": item.name, "subscription": String(item.subscription.rawValue), "timestamp": NSDate(), "ask": item.ask ];
            let dbItem = item as? DBRosterItem ?? DBRosterItem(rosterItem: item);
            if dbItem.id == nil {
                // adding roster item to DB
                dbItem.id = try insertItemStmt.insert(params);
            } else {
                // updating roster item in DB
                try updateItemStmt.update(params);
                let itemGroupsDeleteParams:[String:Any?] = ["account": sessionObject.userBareJid, "jid": dbItem.jid];
                try deleteItemGroupsStmt.update(itemGroupsDeleteParams);
            }
            
            for group in dbItem.groups {
                let gparams:[String:Any?] = ["name": group];
                var groupId = try! getGroupIdStmt.scalar(gparams);
                if groupId == nil {
                    groupId = try! insertGroupStmt.insert(gparams);
                }
                let igparams:[String:Any?] = ["item_id": dbItem.id, "group_id": groupId];
                try insertItemGroupStmt.insert(igparams);
            }
            return dbItem;
        } catch _ {
            return nil;
        }
    }
    
    public func get(sessionObject: SessionObject, jid:JID) -> RosterItem? {
        var item:DBRosterItem? = nil;
        let params:[String:Any?] = [ "account" : sessionObject.userBareJid, "jid" : jid ];
        var id: Int?;
        var name: String?;
        var subscription = RosterItem.Subscription.none;
        var ask = false;
            
        dispatch_sync_local_queue() {
            try! self.getItemStmt.query(params) { cursor -> Void in
                id = cursor["id"]!;
                name = cursor["name"];
                subscription = RosterItem.Subscription(rawValue: cursor["subscription"]!)!;
                ask = cursor["ask"]!;
            }
            if (id != nil) {
                var groups = [String]();
                try! self.getItemGroupsStmt.query(["item_id": id]) { cursor -> Void in
                    groups.append(cursor["name"]!);
                }
                item = DBRosterItem(jid: jid, id: id, name: name, subscription: subscription, groups: groups, ask: ask);
            }
        }
        return item;
    }
    
    public func removeAll(sessionObject: SessionObject) {
        let params:[String:Any?] = ["account": sessionObject.userBareJid];
        
        dbConnection.dispatch_async_db_queue() {
            do {
                try self.deleteItemsGroupsStmt.execute(params);
                try self.deleteItemsStmt.execute(params);
            } catch _ {
            
            }
        }
    }
    
    public func removeItem(sessionObject: SessionObject, jid:JID) {
        let params:[String:Any?] = ["account": sessionObject.userBareJid, "jid": jid];
        dbConnection.dispatch_async_db_queue() {
            do {
                try self.deleteItemGroupsStmt.execute(params);
                try self.deleteItemStmt.execute(params);
            } catch _ {
            
            }
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
    
    @objc public func accountRemoved(notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            let params:[String:Any?] = ["account": accountStr];
            
            dbConnection.dispatch_async_db_queue() {
                do {
                    try self.deleteItemsGroupsStmt.execute(params);
                    try self.deleteItemsStmt.execute(params);
                } catch _ {
                
                }
            }
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
    
    init(jid: JID, id: Int?, name: String?, subscription: RosterItem.Subscription, groups: [String], ask: Bool) {
        self.id = id;
        super.init(jid: jid, name: name, subscription: subscription, groups: groups, ask: ask);
    }
    
    init(rosterItem item: RosterItem) {
        super.init(jid: item.jid, name: item.name, subscription: item.subscription, groups: item.groups, ask: item.ask);
    }
    
    override func update(name: String?, subscription: RosterItem.Subscription, groups: [String], ask: Bool) -> RosterItem {
        return DBRosterItem(jid: self.jid, id: self.id, name: name, subscription: subscription, groups: groups, ask: ask);
    }
}

