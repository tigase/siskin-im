//
// BaseChatViewControllerWithContextMenuAndToolbar.swift
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

protocol BaseChatViewControllerWithContextMenuAndToolbarDelegate: class {
    
    func getTextOfSelectedRows(paths: [IndexPath], withTimestamps: Bool, handler: (([String])->Void)?);
    
}


class BaseChatViewControllerWithContextMenuAndToolbar: BaseChatViewController {

    weak var contextMenuDelegate: BaseChatViewControllerWithContextMenuAndToolbarDelegate?
    
    @IBOutlet var customToolbar: UIToolbar?;
    @IBOutlet var customToolbarHeightConstraint: NSLayoutConstraint?;
    @IBOutlet var bottomViewHeightConstraint: NSLayoutConstraint?;

    fileprivate weak var timestampsSwitch: UIBarButtonItem? = nil;
    fileprivate var withTimestamps: Bool {
        get {
            return Settings.CopyMessagesWithTimestamps.getBool();
        }
        set {
            Settings.CopyMessagesWithTimestamps.setValue(newValue);
        }
    };
    
    override func viewWillAppear(_ animated: Bool) {
        bottomViewHeightConstraint?.isActive = false;
        var items: [UIMenuItem] = UIMenuController.shared.menuItems ?? [];
        items.append(UIMenuItem(title: "More..", action: #selector(ChatTableViewCell.actionMore(_:))));
        UIMenuController.shared.menuItems = items;
        
        super.viewWillAppear(animated);
        NotificationCenter.default.addObserver(self, selector: #selector(showEditToolbar), name: NSNotification.Name("tableViewCellShowEditToolbar"), object: nil);
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIMenuController.shared.menuItems = UIMenuController.shared.menuItems?.filter({ it -> Bool in it.action != #selector(ChatTableViewCell.actionMore(_:))});

        super.viewDidDisappear(animated);
    }
    
    @objc func showEditToolbar(_ notification: Notification) {
        guard let cell = notification.object as? UITableViewCell else {
            return;
        }
        let selected = tableView?.indexPath(for: cell);
        UIView.animate(withDuration: 0.3) {
            self.tableView?.isEditing = true;
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3) {
                self.tableView?.selectRow(at: selected, animated: false, scrollPosition: .none);
            }
            
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(BaseChatViewControllerWithContextMenuAndToolbar.editCancelClicked));
            let timestampsSwitch = UIBarButtonItem(title: "Timestamps: \(self.withTimestamps ? "ON" : "OFF")", style: .plain, target: self, action: #selector(BaseChatViewControllerWithContextMenuAndToolbar.switchWithTimestamps));
            self.timestampsSwitch = timestampsSwitch;

            let items = [
                timestampsSwitch,
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(BaseChatViewControllerWithContextMenuAndToolbar.shareSelectedMessages))
//                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ];
            self.customToolbar?.items = items;
            self.customToolbar?.isHidden = false;
            self.customToolbarHeightConstraint?.isActive = false;
            self.bottomViewHeightConstraint?.isActive = true;
            self.bottomPanel.isHidden = true;
        }
    }
    
    func hideEditToolbar() {
        UIView.animate(withDuration: 0.3) {
            self.customToolbar?.isHidden = true;
            self.bottomViewHeightConstraint?.isActive = false;
            self.customToolbarHeightConstraint?.isActive = true;
            self.bottomPanel.isHidden = false;
            self.customToolbar?.items = nil;
            self.navigationItem.rightBarButtonItem = nil;
            self.tableView?.isEditing = false;
        }
    }
    
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
    
    @objc func switchWithTimestamps() {
        withTimestamps = !withTimestamps;
        timestampsSwitch?.title = "Timestamps: \(withTimestamps ? "ON" : "OFF")";
    }
    
    fileprivate func copyMessageInt(paths: [IndexPath]) {
        contextMenuDelegate?.getTextOfSelectedRows(paths: paths, withTimestamps: false) { (texts) in
            UIPasteboard.general.strings = texts;
            UIPasteboard.general.string = texts.joined(separator: "\n");
        };
    }
    
    fileprivate func shareMessageInt(paths: [IndexPath]) {
        contextMenuDelegate?.getTextOfSelectedRows(paths: paths, withTimestamps: withTimestamps) { (texts) in
            let text = texts.joined(separator: "\n");
            let activityController = UIActivityViewController(activityItems: [text], applicationActivities: nil);
            self.navigationController?.present(activityController, animated: true, completion: nil);
        }
    }
    
    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            return true;
        }
        if customToolbar != nil && action == #selector(ChatTableViewCell.actionMore(_:)) {
            return true;
        }
        return false;
    }
    
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        return true;
    }
    
    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            copyMessageInt(paths: [indexPath]);
        }
        hideEditToolbar();
    }
    
}
