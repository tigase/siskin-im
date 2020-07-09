//
// BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar: BaseChatViewControllerWithDataSource, UITableViewDelegate {

    fileprivate weak var timestampsSwitch: UIBarButtonItem? = nil;
    
    override func viewWillAppear(_ animated: Bool) {
        if #available(iOS 13.0, *) {
            
        } else {
            var items: [UIMenuItem] = UIMenuController.shared.menuItems ?? [];
            items.append(UIMenuItem(title: "More..", action: #selector(ChatTableViewCell.actionMore(_:))));
            UIMenuController.shared.menuItems = items;
        }
        
        super.viewWillAppear(animated);
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIMenuController.shared.menuItems = UIMenuController.shared.menuItems?.filter({ it -> Bool in it.action != #selector(ChatTableViewCell.actionMore(_:))});

        super.viewDidDisappear(animated);
    }
    
    override func initialize(tableView: UITableView) {
        super.initialize(tableView: tableView);
        tableView.delegate = self;
    }
    
    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        if #available(iOS 13.0, *) {
        } else {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            return true;
        }
//        if customToolbar != nil && action == #selector(ChatTableViewCell.actionMore(_:)) {
//            return true;
//        }
        }
        return false;
    }
    
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        if #available(iOS 13.0, *) {
            return false;
        } else {
            return true;
        }
    }
    
    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            conversationLogController?.copyMessageInt(paths: [indexPath]);
        }
        conversationLogController?.hideEditToolbar();
    }
    
    @available(iOS 13.0, *)
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: {
            let cell = self.tableView(tableView, cellForRowAt: indexPath);
            cell.contentView.transform = .identity;
            let view = UIViewController();
            let size = self.conversationLogController!.tableView.rectForRow(at: indexPath).size;
            print("cell:", (cell as? ChatTableViewCell)?.messageTextView.text);
            view.view = cell.contentView;
            view.preferredContentSize = size;
            print("view size:", view.preferredContentSize)
            return view;
        }) { suggestedActions -> UIMenu? in
            return self.prepareContextMenu(for: indexPath);
        };
    }
    
    @available(iOS 13.0, *)
    func prepareContextMenu(for indexPath: IndexPath) -> UIMenu? {
        var items = [
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc"), handler: { action in
                self.conversationLogController?.copyMessageInt(paths: [indexPath]);
            }),
            UIAction(title: "Share..", image: UIImage(systemName: "square.and.arrow.up"), handler: { action in
                self.conversationLogController?.shareMessageInt(paths: [indexPath]);
            })
        ];
        if let dataSource = self.conversationLogController?.dataSource, let item = dataSource.getItem(at: indexPath.row), item.state.direction == .outgoing {
            let row = indexPath.row;
            if let messageItem = item as? ChatMessage, !dataSource.isAnyMatching({ $0.state.direction == .outgoing && $0 is ChatMessage }, in: 0..<row) {
                items.append(UIAction(title: "Correct..", image: UIImage(systemName: "pencil.and.ellipsis.rectangle"), handler: { action in
                    DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
                        DispatchQueue.main.async {
                            self?.startMessageCorrection(message: messageItem.message, originId: originId)
                        }
                    });
                }));
            }
        }
        items.append(contentsOf: [
            UIAction(title: "More..", image: UIImage(systemName: "ellipsis"), handler: { action in
                           guard let cell = self.conversationLogController?.tableView.cellForRow(at: indexPath) else {
                               return;
                           }
                           NotificationCenter.default.post(name: Notification.Name("tableViewCellShowEditToolbar"), object: cell);
            })
        ])
        return UIMenu(title: "", children: items);
    }
}
