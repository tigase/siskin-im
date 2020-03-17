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
            [SettingsEnum.sendMessageOnReturn, SettingsEnum.deleteChatHistoryOnClose, SettingsEnum.enableMessageCarbons, SettingsEnum.messageDeliveryReceipts, SettingsEnum.messageEncryption],
            [SettingsEnum.sharingViaHttpUpload, SettingsEnum.linkPreviews, SettingsEnum.maxImagePreviewSize, SettingsEnum.clearDownloadStore],
                ];
        } else {
            return [
            [SettingsEnum.recentsMessageLinesNo, SettingsEnum.recentsSortType],
            [SettingsEnum.sendMessageOnReturn, SettingsEnum.deleteChatHistoryOnClose, SettingsEnum.enableMessageCarbons, SettingsEnum.messageDeliveryReceipts, SettingsEnum.messageEncryption],
            [SettingsEnum.sharingViaHttpUpload, SettingsEnum.maxImagePreviewSize, SettingsEnum.clearDownloadStore],
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
        case .sharingViaHttpUpload:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SharingViaHttpUploadTableViewCell", for: indexPath ) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.SharingViaHttpUpload.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                if switchView.isOn {
                    let alert = UIAlertController(title: nil, message: "When you share files using HTTP, they are uploaded to HTTP server with unique URL. Anyone who knows the unique URL to the file is able to download it.\nDo you wish to enable?",preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action) in
                        Settings.SharingViaHttpUpload.setValue(true);
                    }));
                    alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: { (action) in
                        switchView.isOn = false;
                    }));
                    self.present(alert, animated: true, completion: nil);
                } else {
                    Settings.SharingViaHttpUpload.setValue(false);
                }
            }
            return cell;
        case .maxImagePreviewSize:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MaxImagePreviewSizeTableViewCell", for: indexPath);
            (cell.contentView.subviews[1] as! UILabel).text = AutoFileDownloadLimit.description(of: Settings.fileDownloadSizeLimit.getInt());
            cell.accessoryType = .disclosureIndicator;
            return cell;
        case .clearDownloadStore:
            return tableView.dequeueReusableCell(withIdentifier: "ClearDownloadStoreTableViewCell", for: indexPath);
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
        case .maxImagePreviewSize:
            let controller = TablePickerViewController(style: .grouped);
            let values: [Int] = [0, 1, 2, 4, 8, 10, 15, 30, 50, Int.max];
            controller.selected = values.firstIndex(of: Settings.fileDownloadSizeLimit.getInt() ) ?? 0;
            controller.items = values.map({ (it)->TablePickerViewItemsProtocol in
                return AutoFileDownloadLimit(value: it);
            });
            //controller.selected = 1;
            controller.onSelectionChange = { (_item) -> Void in
                let item = _item as! AutoFileDownloadLimit;
                Settings.fileDownloadSizeLimit.setValue(item.value);
                self.tableView.reloadData();
            };
            self.navigationController?.pushViewController(controller, animated: true);
        case .clearDownloadStore:
            let alert = UIAlertController(title: "Download storage", message: "We are using \(DownloadStore.instance.size/(1024*1014)) MB of storage.", preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Flush", style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    DownloadStore.instance.clear();
                }
            }));
            alert.addAction(UIAlertAction(title: "Older than 7 days", style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    DownloadStore.instance.clear(olderThan: Date().addingTimeInterval(7*24*60*60.0*(-1.0)));
                }
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            alert.popoverPresentationController?.sourceView = self.tableView;
            alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

            self.present(alert, animated: true, completion: nil);
            break;
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
        case sharingViaHttpUpload = 4
        case maxImagePreviewSize = 5;
        case clearDownloadStore = 6;
        case messageDeliveryReceipts = 7;
        @available(iOS 13.0, *)
        case linkPreviews = 8;
        case sendMessageOnReturn = 9;
        case messageEncryption = 10;
    }
    
    internal class AutoFileDownloadLimit: TablePickerViewItemsProtocol {
        
        public static func description(of value: Int) -> String {
            if value == Int.max {
                return "Unlimited";
            } else {
                return "\(value) MB";
            }
        }
        
        let description: String;
        let value: Int;
        
        init(value: Int) {
            self.value = value;
            self.description = AutoFileDownloadLimit.description(of: value);
        }
        
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
