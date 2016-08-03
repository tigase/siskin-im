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
    var scrollToIndexPath: NSIndexPath? { get set }
}

extension CachedViewControllerProtocol {
    
    func initialize() {
        tableView.transform = cachedDataSource.inverted ? CGAffineTransformMake(1, 0, 0, -1, 0, 0) : CGAffineTransformIdentity;
    }
    
    func newItemAdded() {
        let indexPath = cachedDataSource.newItemAdded();
        self.tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Top);
        self.scrollToIndexPath(indexPath);
    }
    
    func scrollToIndexPath(indexPath: NSIndexPath, animated: Bool = true) {
        self.scrollToIndexPath = indexPath;
        
        dispatch_after( dispatch_time(DISPATCH_TIME_NOW, 30 * Int64(NSEC_PER_MSEC)), dispatch_get_main_queue()) {
            guard self.scrollToIndexPath != nil else {
                return;
            }
            let index = self.scrollToIndexPath!;
            self.scrollToIndexPath = nil;
            
            self.tableView.scrollToRowAtIndexPath(index, atScrollPosition: .Bottom, animated: true);
        }
    }
    
    func tableViewScrollToNewestMessage(animated: Bool) {
        guard let indexPath = cachedDataSource.newestItemIndex() else {
            return;
        }
        
        scrollToIndexPath(indexPath, animated: animated);
    }
    
}

protocol CachedViewDataSourceProtocol {
 
    var inverted: Bool { get set }
    
    func newestItemIndex() -> NSIndexPath?;
    
    func newItemAdded() -> NSIndexPath;
    
}

class CachedViewDataSource<Item: AnyObject>: CachedViewDataSourceProtocol {
    
    var cache = NSCache();
    
    var inverted: Bool = true;
    var numberOfMessages: Int = 0;
    var numberOfMessagesToFetch: Int = 25;
    
    init() {
        cache.countLimit = 100;
        cache.totalCostLimit = 10 * 1024 * 1024;
        numberOfMessages = getItemsCount();
    }
    
    func getItem(indexPath: NSIndexPath) -> Item {
        let requestedPosition = (numberOfMessages - indexPath.row) - 1;
        var item = cache.objectForKey(requestedPosition) as? Item;
        
        if (item == nil) {
            var pos = requestedPosition;
            let down = pos > 0 && cache.objectForKey(pos-1) ==  nil;
            if (down) {
                pos = (pos - numberOfMessagesToFetch) + 1;
                if (pos < 0) {
                    pos = 0;
                }
            }
            
            loadData(pos, limit: numberOfMessagesToFetch, forEveryItem: { (it: Item)->Void in
                self.cache.setObject(it, forKey: pos);
                if requestedPosition == pos {
                    item = it;
                }
                pos += 1;
            });            
        }
        
        return item!;
    }
    
    func newestItemIndex() -> NSIndexPath? {
        guard numberOfMessages > 0 else {
            return nil;
        }
        
        return NSIndexPath(forRow: inverted ? 0 : (numberOfMessages - 1), inSection: 0);
    }
    
    func newItemAdded() -> NSIndexPath {
        let indexPath = NSIndexPath(forRow: inverted ? 0 : numberOfMessages, inSection: 0);
        self.numberOfMessages += 1;
        return indexPath;
    }
    
    func getItemsCount() -> Int {
        return -1;
    }
    
    func loadData(offset: Int, limit: Int, forEveryItem: (Item)->Void) {
        
    }

}

