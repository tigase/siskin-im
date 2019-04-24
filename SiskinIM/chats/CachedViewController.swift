//
// BaseCachedViewController.swift
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
import TigaseSwift

/**
 To use this protocol implement it and assign it to `scrollDelegate` property of
 `BaseChatViewController`. Also remember to initialize it using `initialize()` method.
 */
protocol CachedViewControllerProtocol: BaseChatViewControllerScrollDelegate {
    
    var log: Logger { get }
    
    var scrollToBottomOnShow: Bool { get set }
    var tableView: UITableView! { get set }
    var cachedDataSource: CachedViewDataSourceProtocol { get }
    //var scrollToIndexPath: IndexPath? { get set }
}

extension CachedViewControllerProtocol {
    
    func initialize() {
        tableView.transform = cachedDataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
    }
    
    func newItemAdded(id: Int, timestamp: Date = Date()) {
        let stamp = mach_absolute_time();
        DispatchQueue.main.async {
            if stamp > self.cachedDataSource.resetTime, let indexPath = self.cachedDataSource.newItemAdded(id: id, timestamp: timestamp) {
                self.tableView.insertRows(at: [indexPath], with: .automatic);
                if indexPath.row == 0 {
                    self.scroll(to: indexPath);
                }
            }
        }
    }
    
    func scroll(to indexPath: IndexPath, animated: Bool = true) {
        self.tableView.scrollToRow(at: indexPath , at: .bottom, animated: true);
    }
    
    func tableViewScrollToNewestMessage(animated: Bool) {
        guard let indexPath = cachedDataSource.newestItemIndex() else {
            return;
        }
        
        scroll(to: indexPath, animated: animated);
    }
    
}

protocol CachedViewDataSourceProtocol {
 
    var inverted: Bool { get set }

    var resetTime: UInt64 { get }
    
    func newestItemIndex() -> IndexPath?;
    
    func newItemAdded(id: Int, timestamp: Date) -> IndexPath?;
    
    func reset();
    
}

protocol CachedViewDataSourceItem: class {
    
    var id: Int { get };
    
    var timestamp: Date { get };
    
}

class CachedViewDataSourceItemKey: CachedViewDataSourceItem, CustomStringConvertible {
    
    let id: Int;
    let timestamp: Date;
    
    var description: String {
        return "id: \(id), timestamp: \(timestamp)";
    }
    
    init(id: Int, timestamp: Date) {
        self.id = id;
        self.timestamp = timestamp;
    }
    
}

class CachedViewDataSource<Item: CachedViewDataSourceItem>: NSObject, CachedViewDataSourceProtocol {
    //, NSCacheDelegate {
    
    var list: [CachedViewDataSourceItemKey] = [];
    var cache = NSCache<NSNumber,Item>();
    
    var inverted: Bool = true;
    var numberOfMessages: Int = 0;
    var numberOfMessagesToFetch: Int = 25;
    var resetTime = mach_absolute_time();
    
    override init() {
        cache.countLimit = 100;
        cache.totalCostLimit = 10 * 1024 * 1024;
        super.init();
//        cache.delegate = self;
        self.reset();
    }

//    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
//        guard let it = obj as? CachedViewDataSourceItem else {
//            return;
//        }
//        print("evicting item from cache, id:", it.id, ", ts:", it.timestamp);
//    }
    
    func reset() {
        resetTime = mach_absolute_time();
        numberOfMessages = getItemsCount();
        list.removeAll();
        cache.removeAllObjects();
    }
    
    fileprivate var prevRowIndex = -1;
    
    // does not support non-inverted view!
    func getIndexPath(withId itemId: Int) -> IndexPath? {
        guard let pos = list.firstIndex(where: { (it) -> Bool in
            it.id == itemId
        }) else {
            return nil;
        }
        return IndexPath(row: pos, section: 0);
    }
    
    func getItem(for indexPath: IndexPath) -> Item {
        let down = prevRowIndex >= indexPath.row;
        prevRowIndex = indexPath.row;

        if list.count > indexPath.row {
            let id = list[indexPath.row].id;
            var item = cache.object(forKey: id as NSNumber);
            guard item == nil else {
                return item!;
            }
            
            loadData(afterMessageWithId: id, offset: down ? (1 - numberOfMessagesToFetch) : 0, limit: numberOfMessagesToFetch) { (idx, it) in
                self.cache.setObject(it, forKey: it.id as NSNumber);
                if it.id == id {
                    item = it;
                }
            }
            return item!;
        } else {
            let lastMsgId = list.last?.id;
            let expPos = indexPath.row - list.count;
            let rowsToFetch = max(numberOfMessagesToFetch, expPos + 1);
            
            var item: Item? = nil;
            
            loadData(afterMessageWithId: lastMsgId, offset: list.count == 0 ? 0 : 1, limit: rowsToFetch) { (idx, it) in
                self.cache.setObject(it, forKey: it.id as NSNumber);
                if idx == expPos {
                    item = it;
                }
//                if idx >= list.count {
                    list.append(CachedViewDataSourceItemKey(id: it.id, timestamp: it.timestamp));
//                }
            }

            return item!;
        }
    }
    
    func newestItemIndex() -> IndexPath? {
        guard numberOfMessages > 0 else {
            return nil;
        }
        
        return IndexPath(row: inverted ? 0 : (numberOfMessages - 1), section: 0);
    }
    
    func newItemAdded(id: Int, timestamp: Date) -> IndexPath? {
        //let x = list.index { (it) -> Bool in it.timestamp.compare(timestamp) == .orderedAscending }
        //let pos = list.count == 0 ? 0 : (x ?? list.count);
        var idx: Int? = nil;
        if self.list.firstIndex(where: { (it1) -> Bool in
            it1.id == id
        }) == nil {
            idx = self.list.firstIndex(where: { (it1) -> Bool in it1.timestamp.compare(timestamp) == .orderedAscending });
            self.numberOfMessages += 1;
            if idx != nil {
                let key = CachedViewDataSourceItemKey(id: id, timestamp: timestamp);
                self.list.insert(key, at: idx!)
                print("inserting item at:", idx!, ", key: ", key);
                return IndexPath(row: idx!, section: 0);
//            if numberOfMessages <= idx {
//                // help me!!!
//                print("something went wrong!!!");
//            }
            }
            return IndexPath(row: numberOfMessages - 1, section: 0);
        } else {
            self.numberOfMessages += 1;
            return IndexPath(row: numberOfMessages - 1, section: 0);
        }
        
    }
    
    func getItemsCount() -> Int {
        return -1;
    }
    
    func loadData(afterMessageWithId: Int?, offset: Int, limit: Int, forEveryItem: (Int, Item)->Void) {
        
    }

    enum Direction {
        case next
        case prev
    }
}

