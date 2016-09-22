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
    var scrollToIndexPath: IndexPath? { get set }
}

extension CachedViewControllerProtocol {
    
    func initialize() {
        tableView.transform = cachedDataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
    }
    
    func newItemAdded() {
        let indexPath = cachedDataSource.newItemAdded();
        self.tableView.insertRows(at: [indexPath], with: .top);
        self.scroll(to: indexPath);
    }
    
    func scroll(to indexPath: IndexPath, animated: Bool = true) {
        self.scrollToIndexPath = indexPath;
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + 30 * UInt64(NSEC_PER_MSEC))) {
            guard self.scrollToIndexPath != nil else {
                return;
            }
            let index = self.scrollToIndexPath!;
            self.scrollToIndexPath = nil;
            
            self.tableView.scrollToRow(at: index as IndexPath, at: .bottom, animated: true);
        }
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
    
    func newestItemIndex() -> IndexPath?;
    
    func newItemAdded() -> IndexPath;
    
}

class CachedViewDataSource<Item: AnyObject>: CachedViewDataSourceProtocol {
    
    var cache = NSCache<NSNumber,Item>();
    
    var inverted: Bool = true;
    var numberOfMessages: Int = 0;
    var numberOfMessagesToFetch: Int = 25;
    
    init() {
        cache.countLimit = 100;
        cache.totalCostLimit = 10 * 1024 * 1024;
        numberOfMessages = getItemsCount();
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
    
    func newItemAdded() -> IndexPath {
        let indexPath = IndexPath(row: inverted ? 0 : numberOfMessages, section: 0);
        self.numberOfMessages += 1;
        return indexPath;
    }
    
    func getItemsCount() -> Int {
        return -1;
    }
    
    func loadData(offset: Int, limit: Int, forEveryItem: (Item)->Void) {
        
    }

}

