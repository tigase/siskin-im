//
// ChatSettingsViewController.swift
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

class ChatSettingsViewController: UITableViewController {

    let tree: [[SettingsEnum]] = {
        if #available(iOS 13.0, *) {
            return [
            [SettingsEnum.recentsMessageLinesNo, SettingsEnum.recentsSortType],
            [SettingsEnum.sendMessageOnReturn, SettingsEnum.deleteChatHistoryOnClose, SettingsEnum.enableMessageCarbons, SettingsEnum.messageDeliveryReceipts, SettingsEnum.messageEncryption, SettingsEnum.linkPreviews],
                [SettingsEnum.media]
                ];
        } else {
            return [
            [SettingsEnum.recentsMessageLinesNo, SettingsEnum.recentsSortType],
            [SettingsEnum.sendMessageOnReturn, SettingsEnum.deleteChatHistoryOnClose, SettingsEnum.enableMessageCarbons, SettingsEnum.messageDeliveryReceipts, SettingsEnum.messageEncryption],
                [SettingsEnum.media]
                ];
        }
        }();
    
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
        case 2:
            return "Attachments";
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
            cell.switchView.isOn = Settings.enableMessageCarbons.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.enableMessageCarbons.setValue(switchView.isOn);
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
            (cell.contentView.subviews[1] as! UILabel).text = RecentsSortTypeItem.description(of: ChatsListViewController.SortOrder(rawValue: Settings.RecentsOrder.getString()!)!);
            cell.accessoryType = .disclosureIndicator;
            return cell;
        case .messageDeliveryReceipts:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MessageDeliveryReceiptsTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.MessageDeliveryReceiptsEnabled.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.MessageDeliveryReceiptsEnabled.setValue(switchView.isOn);
            };
            return cell;
        case .linkPreviews:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LinkPreviewsTableViewCell", for: indexPath) as! SwitchTableViewCell;
            if #available(iOS 13.0, *) {
            cell.switchView.isOn = Settings.linkPreviews.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.linkPreviews.setValue(switchView.isOn);
            };
            }
            return cell;
        case .sendMessageOnReturn:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SendMessageOnReturnTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.SendMessageOnReturn.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.SendMessageOnReturn.setValue(switchView.isOn);
            };
            return cell;
        case .messageEncryption:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MessageEncryptionTableViewCell", for: indexPath);
            let label = MessageEncryptionItem.description(of: ChatEncryption(rawValue: Settings.messageEncryption.getString() ?? "") ?? .none);
            (cell.contentView.subviews[1] as! UILabel).text = label;
            cell.accessoryType = .disclosureIndicator;
            return cell;
        case .media:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MediaSettingsViewCell", for: indexPath);
            return cell;
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        let setting = tree[indexPath.section][indexPath.row];
        switch setting {
        case .recentsSortType:
            let controller = TablePickerViewController(style: .grouped);
            let values = [ChatsListViewController.SortOrder.byTime, ChatsListViewController.SortOrder.byAvailablityAndTime];
            controller.selected = values.firstIndex(of: ChatsListViewController.SortOrder(rawValue: Settings.RecentsOrder.getString()!)!) ?? 0;
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
        case .messageEncryption:
            let current = ChatEncryption(rawValue: Settings.messageEncryption.getString() ?? "") ?? .none;
            let controller = TablePickerViewController(style: .grouped);
            let values: [ChatEncryption] = [.none, .omemo];
            controller.selected = values.firstIndex(of: current ) ?? 0;
            controller.items = values.map({ (it)->TablePickerViewItemsProtocol in
                return MessageEncryptionItem(value: it);
            });
            //controller.selected = 1;
            controller.onSelectionChange = { (_item) -> Void in
                let item = _item as! MessageEncryptionItem;
                Settings.messageEncryption.setValue(item.value.rawValue);
                self.tableView.reloadData();
            };
            self.navigationController?.pushViewController(controller, animated: true);

        default:
            break;
        }
    }
    
    internal enum SettingsEnum: Int {
        case deleteChatHistoryOnClose = 0
        case enableMessageCarbons = 1
        case recentsMessageLinesNo = 2
        case recentsSortType = 3
        case messageDeliveryReceipts = 7;
        @available(iOS 13.0, *)
        case linkPreviews = 8;
        case sendMessageOnReturn = 9;
        case messageEncryption = 10;
        case media
    }
    
    internal class MessageEncryptionItem: TablePickerViewItemsProtocol {
        
        public static func description(of value: ChatEncryption) -> String {
            switch value {
            case .omemo:
                return "OMEMO";
            case .none:
                return "None";
            }
        }
        
        let description: String;
        let value: ChatEncryption;
        
        init(value: ChatEncryption) {
            self.value = value;
            self.description = MessageEncryptionItem.description(of: value);
        }
        
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
