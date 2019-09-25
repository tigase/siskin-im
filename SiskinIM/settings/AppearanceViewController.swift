//
// AppearanceViewController.swift
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

class AppearanceViewController: CustomTableViewController {
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath);
        switch indexPath.section {
        case 0:
            let (_, subType) = Appearance.settings();
            cell.detailTextLabel?.text = subType.label;
        case 1:
            switch Appearance.current.colorType {
            case .classic:
                cell.accessoryType = indexPath.row == 0 ? .checkmark : .none;
            case .oriole:
                cell.accessoryType = indexPath.row == 1 ? .checkmark : .none;
            case .purple:
                cell.accessoryType = indexPath.row == 2 ? .checkmark : .none;
            }
        default:
            break;
        }
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        switch indexPath.section {
        case 0:
            let controller = TablePickerViewController(style: .grouped);
            controller.title = "Select theme"
            let (_, subType) = Appearance.settings();
            controller.selected = Appearance.SubColorType.values.firstIndex(where: { (subtype) -> Bool in
                return subtype == subType;
                }) ?? 0;
            controller.items = Appearance.SubColorType.values.map({ (subtype) -> ThemeSelector in
                return ThemeSelector(value: subtype);
            });
            controller.onSelectionChange = { (_item) -> Void in
                let item = _item as! ThemeSelector;
                self.refreshAppearance {
                    Appearance.updateCurrent(colorType: Appearance.current.colorType, subType: item.value);
                }
            }
            self.showDetailViewController(controller, sender: self);
        case 1:
            let subtype = Appearance.current.subtype;
            self.refreshAppearance {
                Appearance.updateCurrent(colorType: self.colorType(forRow: indexPath.row), subType: subtype);
            }
        default:
            break;
        }
    }

    private func refreshAppearance(completionHandler: ()->Void) {
        let tmp = UIViewController();
        let controller = self;
        controller.navigationController?.pushViewController(tmp, animated: true);
        completionHandler();
        DispatchQueue.main.async {
            controller.navigationController?.popViewController(animated: true);
        }
    }
    
    private func colorType(forRow: Int) -> Appearance.ColorType {
        switch forRow {
        case 1:
            return .oriole;
        case 2:
            return .purple;
        default:
            return .classic;
        }
    }
    
    internal class ThemeSelector: TablePickerViewItemsProtocol {
        let description: String;
        let value: Appearance.SubColorType;
        
        init(value: Appearance.SubColorType) {
            self.value = value;
            self.description = value.label;
        }
    }
}
