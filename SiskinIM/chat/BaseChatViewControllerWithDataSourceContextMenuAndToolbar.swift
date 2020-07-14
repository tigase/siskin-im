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
    
    var contextActions: [ContextAction] = [.copy, .reply, .share, .correct, .retract, .more];
    
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
        guard let item = self.conversationLogController?.dataSource.getItem(at: indexPath.row) as? ChatEntry else {
            return nil;
        }
        
        let actions = self.contextActions.filter({ self.canExecuteContext(action: $0, forItem: item, at: indexPath) });
        let items: [UIMenuElement] = actions.map({ action -> UIMenuElement in
            if action.isDesctructive {
                return UIMenu(title: action.title, image: action.image, options: .destructive, children: [
                    UIAction(title: "No", handler: { _ in }),
                    UIAction(title: "Yes", attributes: .destructive, handler: { _ in
                        self.executeContext(action: action, forItem: item, at: indexPath);
                    })
                ]);
            } else {
                return UIAction(title: action.title, image: action.image, handler: { _ in
                    self.executeContext(action: action, forItem: item, at: indexPath);
                })
            }
        })
        
        return UIMenu(title: "", children: items);
    }
    
    public func executeContext(action: ContextAction, forItem item: ChatEntry, at indexPath: IndexPath) {
        switch action {
        case .copy:
            self.conversationLogController?.copyMessageInt(paths: [indexPath]);
        case .reply:
            // something to do..
            self.conversationLogController?.getTextOfSelectedRows(paths: [indexPath], withTimestamps: false, handler: { [weak self] texts in
                let text: String = texts.flatMap { $0.split(separator: "\n")}.map {
                    if $0.starts(with: ">") {
                        return ">\($0)";
                    } else {
                        return "> \($0)"
                    }
                }.joined(separator: "\n");
                
                if let current = self?.messageText, !current.isEmpty {
                    self?.messageText = "\(current)\n\(text)\n";
                } else {
                    self?.messageText = "\(text)\n";
                }
            })
        case .share:
            self.conversationLogController?.shareMessageInt(paths: [indexPath]);
        case .correct:
            DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
                DispatchQueue.main.async {
                    self?.startMessageCorrection(message: (item as! ChatMessage).message, originId: originId)
                }
            });
        case .retract:
            // that is per-chat-type sepecific
            break;
        case .more:
            guard let cell = self.conversationLogController?.tableView.cellForRow(at: indexPath) else {
                return;
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("tableViewCellShowEditToolbar"), object: cell);
            }
        }
    }
    
    public func canExecuteContext(action: ContextAction, forItem item: ChatEntry, at indexPath: IndexPath) -> Bool {
        switch action {
        case .copy:
            return true;
        case .reply:
            return true;
        case .share:
            return true;
        case .correct:
            return item.state.direction == .outgoing && item is ChatMessage && !dataSource.isAnyMatching({ $0.state.direction == .outgoing && $0 is ChatMessage }, in: 0..<indexPath.row);
        case .retract:
            return false;
        case .more:
            return true;
        }
        return false;
    }
    
    public enum ContextAction {
        case copy
        case reply
        case share
        case correct
        case retract
        case more
        
        var title: String {
            switch self {
            case .copy:
                return "Copy";
            case .reply:
                return "Reply..";
            case .share:
                return "Share..";
            case .correct:
                return "Correct..";
            case .retract:
                return "Retract";
            case .more:
                return "More..";
            }
        }
        
        var image: UIImage? {
            guard #available(iOS 13.0, *) else {
                return  nil;
            }
            switch self {
            case .copy:
                return UIImage(systemName: "doc.on.doc");
            case .reply:
                return UIImage(systemName: "arrowshape.turn.up.left");
            case .share:
                return UIImage(systemName: "square.and.arrow.up");
            case .correct:
                return UIImage(systemName: "pencil.and.ellipsis.rectangle");
            case .retract:
                return UIImage(systemName: "trash");
            case .more:
                return UIImage(systemName: "ellipsis");
            }
        }
        
        var isDesctructive: Bool {
            switch self {
            case .retract:
                return true;
            default:
                return false;
            }
        }
    }
}
