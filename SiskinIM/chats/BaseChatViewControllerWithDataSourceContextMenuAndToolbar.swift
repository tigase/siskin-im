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

}
