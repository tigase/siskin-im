//
// BaseChatViewControllerWithDataSource.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class BaseChatViewControllerWithDataSource: BaseChatViewController, ChatViewDataSourceDelegate  {
    
    let dataSource = ChatViewDataSource();
    
    let firstRowIndexPath = IndexPath(row: 0, section: 0);
    
    override func viewDidLoad() {
        super.viewDidLoad();
        dataSource.delegate = self;
        tableView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
     
        self.dataSource.refreshData(unread: chat.unread) { (firstUnread) in
            print("got first unread at:", firstUnread);
            if self.tableView.numberOfRows(inSection: 0) > 0 {
                self.tableView.scrollToRow(at: IndexPath(row: firstUnread ?? 0, section: 0), at: .none, animated: true);
            }
        }
    }
    
    func itemAdded(at rows: IndexSet, shouldScroll: Bool) {
        guard rows.count > 0 else {
            return;
        }
        if dataSource.count == rows.count && rows.count > 1 {
            tableView.reloadData();
        } else {
            let paths = rows.map { (idx) -> IndexPath in
                return IndexPath(row: idx, section: 0);
            }
            tableView.insertRows(at: paths, with: .fade);
        }
        if shouldScroll && rows.contains(0) && (tableView.indexPathsForVisibleRows?.contains(firstRowIndexPath) ?? false) {
            tableView.scrollToRow(at: firstRowIndexPath, at: .none, animated: true)
        }
        markAsReadUpToNewestVisibleRow();
    }
        
    func itemUpdated(indexPath: IndexPath) {
        tableView.reloadRows(at: [indexPath], with: .fade);
        markAsReadUpToNewestVisibleRow();
    }
    
    func itemsRemoved(at rows: IndexSet) {
        let paths = rows.map { (idx) -> IndexPath in
            return IndexPath(row: idx, section: 0);
        }
        tableView.deleteRows(at: paths, with: .fade);
        markAsReadUpToNewestVisibleRow();
    }
    
    func itemsReloaded() {
        tableView.reloadData();
        markAsReadUpToNewestVisibleRow();
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        markAsReadUpToNewestVisibleRow();
    }
    
    func markAsReadUpToNewestVisibleRow() {
        if let visibleRows = tableView.indexPathsForVisibleRows {
            if let newestVisibleUnreadTimestamp = visibleRows.map({ index -> Date? in
                guard let item = dataSource.getItem(at: index.row), item.state.isUnread else {
                    return nil;
                }
                return item.timestamp;
            }).filter({ (date) -> Bool in
                return date != nil;
            }).map({ (date) -> Date in
                return date!
            }).max() {
                DBChatHistoryStore.instance.markAsRead(for: self.account, with: self.jid, before: newestVisibleUnreadTimestamp);
            }
        }
    }
}
