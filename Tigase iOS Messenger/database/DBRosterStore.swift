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

open class DBRosterStoreWrapper: RosterStore {
    
    let cache: NSCache<NSString, RosterItem>?;
    
    let sessionObject: SessionObject;
    let store:DBRosterStore;
    
    override open var count: Int {
        return store.count(for: sessionObject);
    }
    
    init(sessionObject: SessionObject, store: DBRosterStore, useCache: Bool = true) {
        self.sessionObject = sessionObject;
        self.store = store;
        self.cache = useCache ? NSCache() : nil;
        self.cache?.countLimit = 100;
        self.cache?.totalCostLimit = 1 * 1024 * 1024;
        super.init();
    }
    
    override open func addItem(_ item:RosterItem) {
        if let dbItem = store.addItem(for: sessionObject, item: item) {
            cache?.setObject(dbItem, forKey: createKey(jid: dbItem.jid) as NSString);
        }
    }
    
    override open func get(for jid:JID) -> RosterItem? {
        if let item = cache?.object(forKey: createKey(jid: jid) as NSString) {
            return item;
        }
        if let item = store.get(for: sessionObject, jid: jid) {
            cache?.setObject(item, forKey: createKey(jid: jid) as NSString);
            return item;
        }
        return nil;
    }
    
    override open func removeAll() {
        cache?.removeAllObjects();
        store.removeAll(for: sessionObject);
    }
    
    override open func removeItem(for jid:JID) {
        cache?.removeObject(forKey: createKey(jid: jid) as NSString);
        store.removeItem(for: sessionObject, jid: jid);
    }
  
    fileprivate func createKey(jid: JID) -> String {
        guard jid.resource != nil else {
            return jid.bareJid.stringValue.lowercased();
        }
        return "\(jid.bareJid.stringValue.lowercased())/\(jid.resource!)";
    }
}

open class DBRosterStore: RosterCacheProvider, LocalQueueDispatcher {
    
    fileprivate let dbConnection: DBConnection;
    
    fileprivate lazy var countItemsStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM roster_items WHERE account = :account");
    fileprivate lazy var deleteItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items WHERE account = :account AND jid = :jid");
    fileprivate lazy var deleteItemGroupsStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items_groups WHERE item_id IN (SELECT id FROM roster_items WHERE account = :account AND jid = :jid)");
    fileprivate lazy var deleteItemsStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items WHERE account = :account");
    fileprivate lazy var deleteItemsGroupsStmt: DBStatement! = try? self.dbConnection.prepareStatement("DELETE FROM roster_items_groups WHERE item_id IN (SELECT id FROM roster_items WHERE account = :account)");
    
    fileprivate lazy var getGroupIdStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT id from roster_groups WHERE name = :name");
    fileprivate lazy var getItemGroupsStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT name FROM roster_groups rg INNER JOIN roster_items_groups rig ON rig.group_id = rg.id WHERE rig.item_id = :item_id");
    fileprivate lazy var getItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("SELECT id, name, subscription, ask FROM roster_items WHERE account = :account AND jid = :jid");
    
    fileprivate lazy var insertGroupStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO roster_groups (name) VALUES (:name)");
    fileprivate lazy var insertItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO roster_items (account, jid, name, subscription, timestamp, ask) VALUES (:account, :jid, :name, :subscription, :timestamp, :ask)");
    fileprivate lazy var insertItemGroupStmt: DBStatement! = try? self.dbConnection.prepareStatement("INSERT INTO roster_items_groups (item_id, group_id) VALUES (:item_id, :group_id)");
    fileprivate lazy var updateItemStmt: DBStatement! = try? self.dbConnection.prepareStatement("UPDATE roster_items SET name = :name, subscription = :subscription, timestamp = :timestamp, ask = :ask WHERE account = :account AND jid = :jid");
    
    open var queue: DispatchQueue = DispatchQueue(label: "db_roster_store_queue");
    open var queueTag: DispatchSpecificKey<DispatchQueue?>;
    
    public init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        self.queueTag = DispatchSpecificKey<DispatchQueue?>();
        queue.setSpecific(key: queueTag, value: queue);

        NotificationCenter.default.addObserver(self, selector: #selector(DBRosterStore.accountRemoved), name: NSNotification.Name(rawValue: "accountRemoved"), object: nil);
    }
    
    deinit {
        queue.setSpecific(key: queueTag, value: nil);
    }
    
    open func count(for sessionObject: SessionObject) -> Int {
        do {
            let params:[String:Any?] = ["account" : sessionObject.userBareJid!.stringValue];
            return try countItemsStmt.scalar(params) ?? 0;
        } catch _ {
            
        }
        return 0;
    }
    
    open func addItem(for sessionObject: SessionObject, item:RosterItem) -> RosterItem? {
        do {
            let params:[String:Any?] = [ "account": sessionObject.userBareJid, "jid": item.jid, "name": item.name, "subscription": String(item.subscription.rawValue), "timestamp": NSDate(), "ask": item.ask ];
            let dbItem = item as? DBRosterItem ?? DBRosterItem(rosterItem: item);
            if dbItem.id == nil {
                // adding roster item to DB
                dbItem.id = try insertItemStmt.insert(params);
            } else {
                // updating roster item in DB
                _ = try updateItemStmt.update(params);
                let itemGroupsDeleteParams:[String:Any?] = ["account": sessionObject.userBareJid, "jid": dbItem.jid];
                _ = try deleteItemGroupsStmt.update(itemGroupsDeleteParams);
            }
            
            for group in dbItem.groups {
                let gparams:[String:Any?] = ["name": group];
                var groupId = try! getGroupIdStmt.scalar(gparams);
                if groupId == nil {
                    groupId = try! insertGroupStmt.insert(gparams);
                }
                let igparams:[String:Any?] = ["item_id": dbItem.id, "group_id": groupId];
                _ = try insertItemGroupStmt.insert(igparams);
            }
            return dbItem;
        } catch _ {
            return nil;
        }
    }
    
    open func get(for sessionObject: SessionObject, jid:JID) -> RosterItem? {
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
    
    open func removeAll(for sessionObject: SessionObject) {
        let params:[String:Any?] = ["account": sessionObject.userBareJid];
        
        dbConnection.dispatch_async_db_queue() {
            do {
                _ = try self.deleteItemsGroupsStmt.execute(params);
                _ = try self.deleteItemsStmt.execute(params);
            } catch _ {
            
            }
        }
    }
    
    open func removeItem(for sessionObject: SessionObject, jid:JID) {
        let params:[String:Any?] = ["account": sessionObject.userBareJid, "jid": jid];
        dbConnection.dispatch_async_db_queue() {
            do {
                _ = try self.deleteItemGroupsStmt.execute(params);
                _ = try self.deleteItemStmt.execute(params);
            } catch _ {
            
            }
        }
    }
    
    open func getCachedVersion(_ sessionObject: SessionObject) -> String? {
        return AccountManager.getAccount(forJid: sessionObject.userBareJid!.stringValue)?.rosterVersion;
    }
    
    open func loadCachedRoster(_ sessionObject: SessionObject) -> [RosterItem] {
        return [RosterItem]();
    }
    
    open func updateReceivedVersion(_ sessionObject: SessionObject, ver: String?) {
        if let account = AccountManager.getAccount(forJid: sessionObject.userBareJid!.stringValue) {
            account.rosterVersion = ver;
            AccountManager.updateAccount(account, notifyChange: false);
        }
    }
    
    @objc open func accountRemoved(_ notification: NSNotification) {
        if let data = notification.userInfo {
            let accountStr = data["account"] as! String;
            let params:[String:Any?] = ["account": accountStr];
            
            dbConnection.dispatch_async_db_queue() {
                do {
                    _ = try self.deleteItemsGroupsStmt.execute(params);
                    _ = try self.deleteItemsStmt.execute(params);
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

