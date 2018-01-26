//
// BaseCachedViewController.swift
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
    
    func newItemAdded(timestamp: Date = Date()) {
        let stamp = mach_absolute_time();
        DispatchQueue.main.async {
            if stamp > self.cachedDataSource.resetTime, let indexPath = self.cachedDataSource.newItemAdded(timestamp: timestamp) {
                self.tableView.insertRows(at: [indexPath], with: .automatic);
                self.scroll(to: indexPath);
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
    
    func newItemAdded(timestamp: Date) -> IndexPath?;
    
    func reset();
    
}

protocol CachedViewDataSourceItem: class {
    
    var id: Int { get };
    
    var timestamp: Date { get };
    
}

class CachedViewDataSource<Item: CachedViewDataSourceItem>: CachedViewDataSourceProtocol {
    
    var cache = NSCache<NSNumber,Item>();
    
    var inverted: Bool = true;
    var numberOfMessages: Int = 0;
    var numberOfMessagesToFetch: Int = 25;
    var resetTime = mach_absolute_time();
    
    init() {
        cache.countLimit = 100;
        cache.totalCostLimit = 10 * 1024 * 1024;
        self.reset();
    }

    func reset() {
        resetTime = mach_absolute_time();
        numberOfMessages = getItemsCount();
        cache.removeAllObjects();
    }
    
    // does not support non-inverted view!
    func getIndexPath(withId itemId: Int) -> IndexPath? {
        var i = (numberOfMessages);
        var item: Item? = nil;
        repeat {
            i = i - 1;
            item = cache.object(forKey: i as NSNumber);
        } while ((item == nil || item!.id != itemId) && i >= 0);
        
        return i < 0 ? nil : IndexPath(row: (numberOfMessages - i) - 1, section: 0);
    }
    
    func getItem(for indexPath: IndexPath) -> Item {
        let requestedPosition = (numberOfMessages - indexPath.row) - 1;
        var item = cache.object(forKey: requestedPosition as NSNumber);
        if (item == nil) {
            var pos = requestedPosition;
            let down = pos > 0 && cache.object(forKey: pos-1 as NSNumber) ==  nil;
            if (down) {
                pos = (pos - numberOfMessagesToFetch) + 1;
                if (pos < 0) {
                    pos = 0;
                }
            }
            
            loadData(offset: pos, limit: numberOfMessagesToFetch, forEveryItem: { (it: Item)->Void in
                self.cache.setObject(it, forKey: pos as NSNumber);
                if requestedPosition == pos {
                    item = it;
                }
                pos += 1;
            });            
        }
        
        return item!;
    }
    
    func newestItemIndex() -> IndexPath? {
        guard numberOfMessages > 0 else {
            return nil;
        }
        
        return IndexPath(row: inverted ? 0 : (numberOfMessages - 1), section: 0);
    }
    
    func newItemAdded(timestamp: Date) -> IndexPath? {
        var i = (numberOfMessages);
        var item: Item? = nil;
        repeat {
            i = i - 1;
            item = cache.object(forKey: i as NSNumber);
        } while ((item == nil || item!.timestamp.compare(timestamp) == .orderedDescending) && i >= 0);
        i = i + 1;
        var j = i;
        while (j < numberOfMessages) {
            cache.removeObject(forKey: j as NSNumber);
            j = j + 1;
        }
        self.numberOfMessages += 1;
        return IndexPath(row: (numberOfMessages - i) - 1, section: 0);
    }
    
    func getItemsCount() -> Int {
        return -1;
    }
    
    func loadData(offset: Int, limit: Int, forEveryItem: (Item)->Void) {
        
    }

}

