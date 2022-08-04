//
// SettingsViewController.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import Martin
import Combine

class SettingsViewController: UITableViewController {
   
    var statusNames: [Presence.Show: String] = [
        .chat : NSLocalizedString("Chat", comment: "presence status"),
        .online : NSLocalizedString("Online", comment: "presence status"),
        .away : NSLocalizedString("Away", comment: "presence status"),
        .xa : NSLocalizedString("Extended away", comment: "presence status"),
        .dnd : NSLocalizedString("Do not disturb", comment: "presence status"),
    ];
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        tableView.reloadData();
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Accounts", comment: "section label");
        case 1:
            return NSLocalizedString("Status", comment: "section label");
        case 2:
            return NSLocalizedString("Settings", comment: "section label");
        case 3:
            return ""
        default:
            return "";
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return nil;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return AccountManager.getAccounts().count + 1;
        case 1:
            return 2;
        case 2:
            return SettingsGroup.groups.count;
        case 3:
            return 2;
        default:
            return 0;
        }
    }
    
    private var statusMessageCancellable: AnyCancellable?;
    private var statusTypeCancellable1: AnyCancellable?;
    private var statusTypeCancellable2: AnyCancellable?;

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section == 0) {
            let cellIdentifier = "AccountTableViewCell";
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! AccountTableViewCell;
            cell.accessoryType = .disclosureIndicator;
            let accounts = AccountManager.getAccounts();
            if accounts.count > indexPath.row {
                cell.avatarStatusView.isHidden = false;
                cell.set(account: accounts[indexPath.row]);
                if AccountSettings.lastError(for :accounts[indexPath.row]) != nil {
                    cell.avatarStatusView.statusImageView.image = UIImage(systemName: "xmark.circle.fill")!;
                }
                cell.avatarStatusView.updateCornerRadius();
            } else {
                cell.nameLabel.text = NSLocalizedString("Add account", comment: "cell label");
                cell.descriptionLabel.text = NSLocalizedString("Create new or add existing account", comment: "cell sublabel");
                cell.avatarStatusView.avatarImageView.image = UIImage(systemName: "plus.circle.fill")?.withTintColor(UIColor(named: "tintColor")!, renderingMode: .alwaysOriginal);
                cell.avatarStatusView.statusImageView.isHidden = true;
            }
            return cell;
        } else if (indexPath.section == 1) {
            if indexPath.row == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTableViewCell", for: indexPath);
                let label = cell.viewWithTag(1)! as! UILabel;
                self.statusMessageCancellable = Settings.$statusMessage.assign(to: \.text, on: label);
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTypeSettingsViewCell", for: indexPath);
                self.statusTypeCancellable1 = Settings.$statusType.map({ [weak self] v in self?.getStatusIcon(type: v) }).sink(receiveValue: { [weak cell] image in
                    if image == nil {
                        (cell?.contentView.subviews[0] as? UIImageView)?.isHidden = true;
                    } else {
                        (cell?.contentView.subviews[0] as? UIImageView)?.image = image;
                        (cell?.contentView.subviews[0] as? UIImageView)?.isHidden = false;
                    }
                });
                self.statusTypeCancellable2 = Settings.$statusType.map({ [weak self] type in
                    if let value = type {
                        return self?.statusNames[value];
                    } else {
                        return NSLocalizedString("Automatic", comment: "presence status");
                    }
                }).sink(receiveValue: { [weak cell] name in
                    (cell?.contentView.subviews[1] as? UILabel)?.text = name;
                });
                cell.accessoryType = .disclosureIndicator;
                return cell;
            }
        } else if (indexPath.section == 2) {
            switch SettingsGroup.groups[indexPath.row] {
            case .appearance:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AppearanceViewCell", for: indexPath) as! EnumTableViewCell;
                cell.bind({ cell in
                    cell.assign(from: Settings.$appearance.map({ $0.description as String? }).eraseToAnyPublisher());
                })
                cell.accessoryType = .disclosureIndicator;
                return cell;
            case .chat:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ChatSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            case .contacts:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ContactsSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            case .notifications:
                let cell = tableView.dequeueReusableCell(withIdentifier: "NotificationSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            case .media:
                let cell = tableView.dequeueReusableCell(withIdentifier: "MediaSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            case .experimental:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ExperimentalSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            }
        } else {
            switch AboutGroup.groups[indexPath.row] {
            case .getInTouch:
                let cell = tableView.dequeueReusableCell(withIdentifier: "GetInTouchSettingsViewCell", for: indexPath);
                return cell;
            case .aboutTheApp:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AboutSettingsViewCell", for: indexPath);
                return cell;
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let accountCell = cell as? AccountTableViewCell {
            accountCell.avatarStatusView.updateCornerRadius();
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
        
        if indexPath.section == 0 {
            let accounts = AccountManager.getAccounts();
            if indexPath.row == accounts.count {
                let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
                alert.addAction(UIAlertAction(title: NSLocalizedString("Create new", comment: "button label"), style: .default, handler: { (action) in
                    self.showAddAccount(register: true);
                }));
                alert.addAction(UIAlertAction(title: NSLocalizedString("Add existing", comment: "button label"), style: .default, handler: { (action) in
                    self.showAddAccount(register: false);
                }));
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
                alert.popoverPresentationController?.sourceView = self.tableView;
                alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

                self.present(alert, animated: true, completion: nil);
            } else {
                // show edit account dialog
                let account = accounts[indexPath.row];
                let accountSettingsController = AccountSettingsViewController.instantiate(fromAppStoryboard: .Account);
                accountSettingsController.hidesBottomBarWhenPushed = true;
                accountSettingsController.account = account;
                self.navigationController?.pushViewController(accountSettingsController, animated: true);
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                let alert = UIAlertController(title: NSLocalizedString("Select status", comment: "alert title"), message: nil, preferredStyle: .actionSheet);
                let options: [Presence.Show?] = [nil, .chat, .online, .away, .xa, .dnd];
                for type in options {
                    let name = type == nil ? NSLocalizedString("Automatic", comment: "presence automatic") : self.statusNames[type!];
                    let action = UIAlertAction(title: name, style: .default) { (a) in
                        Settings.statusType = type;
                    };
                    if type != nil {
                        action.setValue(getStatusIcon(type: type!), forKey: "image")
                    }
                    alert.addAction(action);
                }
            
                let action = UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil);
                alert.addAction(action);
                
                alert.popoverPresentationController?.sourceView = self.tableView;
                alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);
                
                self.present(alert, animated: true, completion: nil);
            }
            else if indexPath.row == 1 {
                let alert = UIAlertController(title: NSLocalizedString("Status", comment: "alert title"), message: NSLocalizedString("Enter status message", comment: "alert body"), preferredStyle: .alert);
                alert.addTextField(configurationHandler: { (textField) in
                    textField.text = Settings.statusMessage;
                })
                alert.addAction(UIAlertAction(title: NSLocalizedString("Set", comment: "button label"), style: .default, handler: { (action) -> Void in
                    Settings.statusMessage = (alert.textFields![0] as UITextField).text;
                    self.tableView.reloadData();
                }));
                self.present(alert, animated: true, completion: nil);
            }
        } else if indexPath.section == 2 {
            switch SettingsGroup.groups[indexPath.row] {
            case .appearance:
                let controller = TablePickerViewController<Appearance>(style: .grouped, message: NSLocalizedString("Select appearance", comment: "selection information"), options: [.auto, .light, .dark], value: Settings.appearance);
                controller.sink(to: \.appearance, on: Settings);
                self.navigationController?.pushViewController(controller, animated: true);
            default:
                break;
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false;
    }
        
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        (segue.destination as? UINavigationController)?.visibleViewController?.hidesBottomBarWhenPushed = true;
    }
            
    func showAddAccount(register: Bool) {
        // show add account dialog
        if !register {
            let addAccountController = AddAccountController.instantiate(fromAppStoryboard: .Account);
            addAccountController.hidesBottomBarWhenPushed = true;
            self.navigationController?.pushViewController(addAccountController, animated: true);
        } else {
            let registerAccountController = RegisterAccountController.instantiate(fromAppStoryboard: .Account);
            registerAccountController.hidesBottomBarWhenPushed = true;
            self.navigationController?.pushViewController(registerAccountController, animated: true);
        }
    }
    
    private func getStatusIcon(type: Presence.Show?) -> UIImage? {
        guard let show = type else {
            return nil;
        }
        return AvatarStatusView.getStatusImage(show);
    }
 
    @IBAction func closeClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }
    
    enum SettingsGroup {
        case appearance
        case chat
        case contacts
        case notifications
        case media
        case experimental
        //case about
        
        static let groups: [SettingsGroup] = [.appearance, .chat, .contacts, .notifications, .media, .experimental];
    }
    
    enum AboutGroup {
        case getInTouch
        case aboutTheApp
        
        static let groups: [AboutGroup] = [.getInTouch, .aboutTheApp]
    }
}
