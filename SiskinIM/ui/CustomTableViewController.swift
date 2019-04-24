//
// CustomTableViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class CustomTableViewController: UITableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: Appearance.CHANGED, object: nil);
        updateAppearance();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.navigationController?.navigationBar.isTranslucent = false;
        updateAppearance();
    }
    
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewWillAppear(animated);
//        self.navigationController?.navigationBar.isTranslucent = false;
//        updateAppearance();
//    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = Appearance.current.tableViewCellBackgroundColor();
//        cell.tintColor = Appearance.current.tintColor();
        updateSubviews(view: cell);
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.backgroundView?.backgroundColor = Appearance.current.tableViewHeaderFooterBackgroundColor();
            headerView.textLabel?.textColor = Appearance.current.tableViewHeaderFooterTextColor();
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.backgroundView?.backgroundColor = Appearance.current.tableViewHeaderFooterBackgroundColor();
            headerView.textLabel?.textColor = Appearance.current.tableViewHeaderFooterTextColor();
        }
    }
    
    fileprivate func updateSubviews(view v: UIView) {
        v.subviews.forEach({ (view) in
            updateSubviews(view: view);
            if let label = view as? UILabel {
                if label.accessibilityTraits.contains(UIAccessibilityTraits.link) {
                    label.textColor = Appearance.current.tintColor();
                } else {
                    label.textColor = Appearance.current.textColor();
                }
            }
            if let textField = view as? UITextField {
                if textField.inputView is UIPickerView {
                    textField.textColor = Appearance.current.tintColor();
                } else {
                    textField.textColor = Appearance.current.textColor();
                    textField.backgroundColor = Appearance.current.textBackgroundColor();
                    if textField.borderStyle != .none {
                        textField.layer.borderColor = Appearance.current.textFieldBorderColor().cgColor;
                        textField.layer.borderWidth = 1.0;
                        textField.layer.cornerRadius = 8.0;
                    }
                }
                //                (textField.inputView as? UIPickerView)?.backgroundColor = Appearance.current.textBackgroundColor();
                //                (textField.inputView as? UIPickerView)?.tintColor = Appearance.current.tintColor();
                textField.attributedPlaceholder = NSAttributedString(string: textField.placeholder ?? "", attributes: [ .foregroundColor: Appearance.current.placeholderColor()])
                textField.keyboardAppearance = Appearance.current.isDark ? .dark : .light;
            }
        });
    }
    
    @objc func appearanceChanged(_ notification: Notification) {
        self.updateAppearance();
    }
    
    func updateAppearance() {
        self.view.tintColor = Appearance.current.tintColor();
        
        // TODO: Alternative approach to add different colors to the primary view..
//        if self is RosterViewController || self is SettingsViewController || self is ChatsListViewController {
//            self.tableView.backgroundColor = Appearance.current.tableViewBackgroundColor().adjust(brightness: Appearance.current.isDark ? 0.15 : 0.95) //Appearance.current.tableViewBackgroundColor().darker(ratio: 0.05);
//            self.tableView.separatorColor = Appearance.current.tableViewSeparatorColor().darker(ratio: 0.05);
//        } else {
//            self.tableView.backgroundColor = Appearance.current.tableViewBackgroundColor();
//            self.tableView.separatorColor = Appearance.current.tableViewSeparatorColor();
//        }
        
        self.tableView.backgroundColor = self.tableView.style == .grouped ? Appearance.current.tableViewHeaderFooterBackgroundColor() : Appearance.current.tableViewBackgroundColor();
        self.tableView.separatorColor = Appearance.current.tableViewSeparatorColor();

        if let navController = self.navigationController {
            navController.navigationBar.barStyle = Appearance.current.navigationBarStyle();
            navController.navigationBar.tintColor = Appearance.current.navigationBarTintColor();
            navController.navigationBar.barTintColor = Appearance.current.controlBackgroundColor();
            navController.navigationBar.setNeedsLayout();
            navController.navigationBar.layoutIfNeeded();
            navController.navigationBar.setNeedsDisplay();
        }
        DispatchQueue.main.async {
            self.tableView.reloadData();
        }
    }
}
