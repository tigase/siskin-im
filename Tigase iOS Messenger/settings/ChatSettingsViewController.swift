//
// ChatSettingsViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class ChatSettingsViewController: UITableViewController {

    let tree: [[SettingsEnum]] = [
        [SettingsEnum.recentsMessageLinesNo, SettingsEnum.recentsSortType],
        [SettingsEnum.deleteChatHistoryOnClose, SettingsEnum.enableMessageCarbons],
    ];
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return tree.count;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tree[section].count;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "List of messages"
        case 1:
            return "Messages";
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = tree[indexPath.section][indexPath.row];
        switch setting {
        case .deleteChatHistoryOnClose:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DeleteChatHistoryOnCloseTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.DeleteChatHistoryOnChatClose.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.DeleteChatHistoryOnChatClose.setValue(switchView.isOn);
            }
            return cell;
        case .enableMessageCarbons:
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnableMessageCarbonsTableViewCell", for: indexPath ) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.EnableMessageCarbons.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.EnableMessageCarbons.setValue(switchView.isOn);
            }
            return cell;
        case .recentsMessageLinesNo:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RecentsMessageLinesNoTableViewCell", for: indexPath ) as! StepperTableViewCell;
            cell.updateLabel = { (val) -> String? in
                if val == 1 {
                    return "1 line of preview";
                } else {
                    return Int(val).description + " lines of preview";
                }
            };
            cell.setValue(Double(Settings.RecentsMessageLinesNo.getInt()));
            cell.valueChangedListener = {(stepperView: UIStepper) in
                Settings.RecentsMessageLinesNo.setValue(Int(stepperView.value));
            };
            return cell;
        case .recentsSortType:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RecentsSortTypeTableViewCell", for: indexPath );
            (cell.contentView.subviews[0].subviews[1] as! UILabel).text = RecentsSortTypeItem.description(of: ChatsListViewController.SortOrder(rawValue: Settings.RecentsOrder.getString()!)!);
            cell.accessoryType = .disclosureIndicator;
            return cell;
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        let setting = tree[indexPath.section][indexPath.row];
        if setting == .recentsSortType {
            let controller = TablePickerViewController(style: .grouped);
            let values = [ChatsListViewController.SortOrder.byTime, ChatsListViewController.SortOrder.byAvailablityAndTime];
            controller.selected = values.index(of: ChatsListViewController.SortOrder(rawValue: Settings.RecentsOrder.getString()!)!) ?? 0;
            controller.items = values.map({ (it)->TablePickerViewItemsProtocol in
                return RecentsSortTypeItem(value: it);
            });
            //controller.selected = 1;
            controller.onSelectionChange = { (_item) -> Void in
                let item = _item as! RecentsSortTypeItem;
                Settings.RecentsOrder.setValue(item.value.rawValue);
                self.tableView.reloadData();
            };
            self.navigationController?.pushViewController(controller, animated: true);
        }
    }
    
    internal enum SettingsEnum: Int {
        case deleteChatHistoryOnClose = 0
        case enableMessageCarbons = 1
        case recentsMessageLinesNo = 2
        case recentsSortType = 3
    }
    
    internal class RecentsSortTypeItem: TablePickerViewItemsProtocol {
        
        public static func description(of value: ChatsListViewController.SortOrder) -> String {
            switch value {
            case .byTime:
                return "By time";
            case .byAvailablityAndTime:
                return "By availability and time";
            }
        }
        
        let description: String;
        let value: ChatsListViewController.SortOrder;
        
        init(value: ChatsListViewController.SortOrder) {
            self.value = value;
            self.description = RecentsSortTypeItem.description(of: value);
        }
        
    }
}
