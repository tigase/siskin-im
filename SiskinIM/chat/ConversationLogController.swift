//
// ConversationLogController.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

class ConversationLogController: UIViewController, ChatViewDataSourceDelegate {
    
    private let firstRowIndexPath = IndexPath(row: 0, section: 0);

    @IBOutlet var tableView: UITableView!;
    
    let dataSource = ChatViewDataSource();

    var chat: DBChatProtocol!;
        
    weak var conversationLogDelegate: ConversationLogDelegate?;

    var refreshControl: UIRefreshControl?;
    
    private var loaded: Bool = false;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        dataSource.delegate = self;

        tableView.rowHeight = UITableView.automaticDimension;
        tableView.estimatedRowHeight = 160.0;
        tableView.separatorStyle = .none;
        tableView.transform = dataSource.inverted ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0) : CGAffineTransform.identity;
        
        if let refreshControl = self.refreshControl {
            tableView.addSubview(refreshControl);
        }
        
        conversationLogDelegate?.initialize(tableView: self.tableView);
        
        NotificationCenter.default.addObserver(self, selector: #selector(showEditToolbar), name: NSNotification.Name("tableViewCellShowEditToolbar"), object: nil);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        if !loaded {
            loaded = true;
            self.dataSource.refreshData(unread: chat.unread) { (firstUnread) in
                print("got first unread at:", firstUnread);
                if self.tableView.numberOfRows(inSection: 0) > 0 {
                    self.tableView.scrollToRow(at: IndexPath(row: firstUnread ?? 0, section: 0), at: .none, animated: true);
                }
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
            print("added items at:", rows, "scrolling to:", firstRowIndexPath);
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
        //super.scrollViewDidScroll(scrollView);
        markAsReadUpToNewestVisibleRow();
    }
    
    func markAsReadUpToNewestVisibleRow() {
        if let chat = self.chat, let visibleRows = tableView.indexPathsForVisibleRows, chat.unread > 0 {
            if let newestVisibleUnreadTimestamp = visibleRows.map({ index -> Date? in
                guard let item = dataSource.getItem(at: index.row) else {
                    return nil;
                }
                return item.timestamp;
            }).filter({ (date) -> Bool in
                return date != nil;
            }).map({ (date) -> Date in
                return date!
            }).max() {
                DBChatHistoryStore.instance.markAsRead(for: chat.account, with: chat.jid.bareJid, before: newestVisibleUnreadTimestamp);
            }
        }
    }

    func reloadVisibleItems() {
        if let indexPaths = self.tableView.indexPathsForVisibleRows {
            self.tableView.reloadRows(at: indexPaths, with: .none);
        }
    }
        
    private var tempRightBarButtonItem: UIBarButtonItem?;
}

extension ConversationLogController {
    
    private var withTimestamps: Bool {
        get {
            return Settings.CopyMessagesWithTimestamps.getBool();
        }
    };
        
    @objc func editCancelClicked() {
        hideEditToolbar();
    }
    
    func copySelectedMessages() {
        copyMessageInt(paths: tableView.indexPathsForSelectedRows ?? []);
        hideEditToolbar();
    }

    @objc func shareSelectedMessages() {
        shareMessageInt(paths: tableView.indexPathsForSelectedRows ?? []);
        hideEditToolbar();
    }

    func copyMessageInt(paths: [IndexPath]) {
        getTextOfSelectedRows(paths: paths, withTimestamps: false) { (texts) in
            UIPasteboard.general.strings = texts;
            UIPasteboard.general.string = texts.joined(separator: "\n");
        };
    }
    
    func shareMessageInt(paths: [IndexPath]) {
        getTextOfSelectedRows(paths: paths, withTimestamps: withTimestamps) { (texts) in
            let text = texts.joined(separator: "\n");
            let activityController = UIActivityViewController(activityItems: [text], applicationActivities: nil);
            let visible = self.tableView.indexPathsForVisibleRows ?? [];
            if let firstVisible = visible.first(where:{ (indexPath) -> Bool in
                return paths.contains(indexPath);
                }) ?? visible.first {
                activityController.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: firstVisible);
                activityController.popoverPresentationController?.sourceView = self.tableView.cellForRow(at: firstVisible);
                self.navigationController?.present(activityController, animated: true, completion: nil);
            }
        }
    }
    
    @objc func showEditToolbar(_ notification: Notification) {
        guard let cell = notification.object as? UITableViewCell else {
            return;
        }

        DispatchQueue.main.async {
            self.view.endEditing(true);
            DispatchQueue.main.async {
                let selected = self.tableView?.indexPath(for: cell);
                UIView.animate(withDuration: 0.3) {
                    self.tableView?.isEditing = true;
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3) {
                        self.tableView?.selectRow(at: selected, animated: false, scrollPosition: .none);
                    }
                
                    self.tempRightBarButtonItem = self.conversationLogDelegate?.navigationItem.rightBarButtonItem;
                    self.conversationLogDelegate?.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(ConversationLogController.editCancelClicked));
                
                    let timestampsSwitch = TimestampsBarButtonItem();
                    self.conversationLogDelegate?.navigationController?.toolbar.tintColor = UIColor(named: "tintColor");
                    print("navigationController:", self.navigationController as Any)
                    let items = [
                        timestampsSwitch,
                        UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                        UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(ConversationLogController.shareSelectedMessages))
                        //                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
                    ];
                
                    self.conversationLogDelegate?.navigationController?.setToolbarHidden(false, animated: true);
                    self.conversationLogDelegate?.setToolbarItems(items, animated: true);
                }
            }
        }
    }
        
    func hideEditToolbar() {
        UIView.animate(withDuration: 0.3) {
            self.conversationLogDelegate?.navigationController?.setToolbarHidden(true, animated: true);
            self.conversationLogDelegate?.setToolbarItems(nil, animated: true);
            self.conversationLogDelegate?.navigationItem.rightBarButtonItem = self.tempRightBarButtonItem;
            self.tableView?.isEditing = false;
        }
    }
    
    func getTextOfSelectedRows(paths: [IndexPath], withTimestamps: Bool, handler: (([String]) -> Void)?) {
        let items: [ChatViewItemProtocol] = paths.map({ index in dataSource.getItem(at: index.row)! }).sorted { (it1, it2) -> Bool in
              it1.timestamp.compare(it2.timestamp) == .orderedAscending;
                };
        
        let withoutPrefix = Set(items.map({it in it.state.direction})).count == 1;
    
        let formatter = DateFormatter();
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy jj:mm", options: 0, locale: NSLocale.current);
    
        let texts = items.map { (it) -> String? in
            return it.copyText(withTimestamp: withTimestamps, withSender: !withoutPrefix);
        }.filter { (text) -> Bool in
            return text != nil;
        }.map { (text) -> String in
            return text!;
        };
            
        print("got texts", texts);
        handler?(texts);
    }

    class TimestampsBarButtonItem: UIBarButtonItem {
        
        var value: Bool {
            get {
                Settings.CopyMessagesWithTimestamps.bool();
            }
            set {
                Settings.CopyMessagesWithTimestamps.setValue(newValue);
                updateTimestampSwitch();
            }
        }
        
        override init() {
            super.init();
            self.style = .plain;
            self.target = self;
            self.action = #selector(switchWithTimestamps)
            self.updateTimestampSwitch();
        }
        
        required init?(coder: NSCoder) {
            return nil;
        }
        
        @objc private func switchWithTimestamps() {
            value = !value;
        }
        
        private func updateTimestampSwitch() {
            if #available(iOS 13.0, *) {
                image = UIImage(systemName: value ? "clock.fill" : "clock");
                title = nil;
            } else {
                title = "Timestamps: \(value ? "ON" : "OFF")";
                image = nil;
            }
        }
    }
}

protocol ConversationLogDelegate: class {
 
    var navigationItem: UINavigationItem { get }
    var navigationController: UINavigationController? { get }
    
    func initialize(tableView: UITableView);
    
    func setToolbarItems(_ toolbarItems: [UIBarButtonItem]?,
                         animated: Bool);
}
