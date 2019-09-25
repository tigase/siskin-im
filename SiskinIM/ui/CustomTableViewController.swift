//
// CustomTableViewController.swift
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
        cell.backgroundColor = Appearance.current.systemBackground;
        //cell.tintColor = Appearance.current.tintColor();
        updateSubviews(view: cell);
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.backgroundView?.backgroundColor = Appearance.current.secondarySystemBackground;
            headerView.textLabel?.textColor = Appearance.current.tableViewHeaderFooterTextColor;
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.backgroundView?.backgroundColor = Appearance.current.secondarySystemBackground;
            headerView.textLabel?.textColor = Appearance.current.tableViewHeaderFooterTextColor;
        }
    }
    
    fileprivate func updateSubviews(view v: UIView) {
        v.subviews.forEach({ (view) in
            updateSubviews(view: view);
            if let label = view as? UILabel {
                if label.accessibilityTraits.contains(.summaryElement) {
                    label.textColor = Appearance.current.secondaryLabelColor;
                } else if label.accessibilityTraits.contains(UIAccessibilityTraits.link) {
                    label.textColor = Appearance.current.tintColor;
                } else {
                    label.textColor = Appearance.current.labelColor;
                }
            }
            if let textField = view as? UITextField {
                if textField.inputView is UIPickerView {
                    textField.textColor = Appearance.current.tintColor;
                } else {
                    textField.textColor = Appearance.current.labelColor;
                    textField.backgroundColor = Appearance.current.systemBackground;
                    if textField.borderStyle != .none {
                        textField.layer.borderColor = Appearance.current.textFieldBorderColor.cgColor;
                        textField.layer.borderWidth = 1.0;
                        textField.layer.cornerRadius = 8.0;
                    }
                }
                //                (textField.inputView as? UIPickerView)?.backgroundColor = Appearance.current.textBackgroundColor();
                //                (textField.inputView as? UIPickerView)?.tintColor = Appearance.current.tintColor();
                textField.attributedPlaceholder = NSAttributedString(string: textField.placeholder ?? "", attributes: [ .foregroundColor: Appearance.current.placeholderColor])
                textField.keyboardAppearance = Appearance.current.isDark ? .dark : .light;
            }
        });
    }
    
    @objc func appearanceChanged(_ notification: Notification) {
        self.updateAppearance();
    }
    
    func updateAppearance() {
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = Appearance.current.isDark ? .dark : .light;
        };
        self.view.tintColor = Appearance.current.tintColor;
        
        self.tableView.backgroundColor = self.tableView.style == .grouped ? Appearance.current.secondarySystemBackground: Appearance.current.systemBackground;
        self.tableView.separatorColor = Appearance.current.secondarySystemBackground;

        if let navController = self.navigationController {
            navController.navigationBar.barStyle = Appearance.current.navigationBarStyle;
            navController.navigationBar.tintColor = Appearance.current.navigationBarTintColor;
            navController.navigationBar.barTintColor = Appearance.current.controlBackgroundColor;
            navController.navigationBar.setNeedsLayout();
            navController.navigationBar.layoutIfNeeded();
            navController.navigationBar.setNeedsDisplay();
        }
        DispatchQueue.main.async {
            self.tableView.reloadData();
        }
    }
}
