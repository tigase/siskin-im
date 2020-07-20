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
import TigaseSwift

class SettingsViewController: UITableViewController {
   
    var statusNames = [
        "chat" : "Chat",
        "online" : "Online",
        "away" : "Away",
        "xa" : "Extended away",
        "dnd" : "Do not disturb"
    ];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateChanged), name: XmppService.ACCOUNT_STATE_CHANGED, object: nil);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        tableView.reloadData();
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Accounts";
        case 1:
            return "Status";
        case 2:
            return "Settings";
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
        default:
            return 0;
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section == 0) {
            let cellIdentifier = "AccountTableViewCell";
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! AccountTableViewCell;
            cell.accessoryType = .disclosureIndicator;
            let accounts = AccountManager.getAccounts();
            if accounts.count > indexPath.row {
                cell.avatarStatusView.isHidden = false;
                let account = AccountManager.getAccount(for: accounts[indexPath.row]);
                cell.nameLabel.text = account?.name.stringValue;
                let jid = BareJID(account!.name);
                cell.avatarStatusView.set(name: nil, avatar: AvatarManager.instance.avatar(for: jid, on: jid), orDefault: AvatarManager.instance.defaultAvatar);
                if let client = XmppService.instance.getClient(for: jid) {
                    cell.avatarStatusView.statusImageView.isHidden = false;
                    var status: Presence.Show? = nil;
                    switch client.state {
                    case .connected:
                        status = .online;
                    case .connecting, .disconnecting:
                        status = Presence.Show.xa;
                    default:
                        break;
                    }
                    cell.avatarStatusView.setStatus(status);
                } else if AccountSettings.LastError(jid).getString() != nil {
                    cell.avatarStatusView.statusImageView.isHidden = false;
                    cell.avatarStatusView.statusImageView.image = UIImage(named: "presence_error")!;
                } else {
                    cell.avatarStatusView.statusImageView.isHidden = true;
                }
                cell.avatarStatusView.updateCornerRadius();
            } else {
                cell.nameLabel.text = "Add account";
                cell.avatarStatusView.avatarImageView.image = nil;
                cell.avatarStatusView.isHidden = true;
            }
            return cell;
        } else if (indexPath.section == 1) {
            if indexPath.row == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTableViewCell", for: indexPath);
                let label = cell.viewWithTag(1)! as! UILabel;
                label.text = Settings.StatusMessage.getString();
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "StatusTypeSettingsViewCell", for: indexPath);
                let type = Settings.StatusType.getString();
                if let image = type != nil ? getStatusIconForActionIcon(named: "presence_\(type!)", size: 55, withBorder: false) : nil {
                    (cell.contentView.subviews[0] as? UIImageView)?.image = image;
                    (cell.contentView.subviews[0] as? UIImageView)?.isHidden = false;
                } else {
                    (cell.contentView.subviews[0] as? UIImageView)?.isHidden = true;
                }
                (cell.contentView.subviews[1] as? UILabel)?.text = type != nil ? self.statusNames[type!] : "Automatic";
                cell.accessoryType = .disclosureIndicator;
                return cell;
            }
        } else {
            switch SettingsGroup.groups[indexPath.row] {
            case .appearance:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AppearanceViewCell", for: indexPath);
                if #available(iOS 13.0, *) {
                    if let style = self.view.window?.overrideUserInterfaceStyle {
                        cell.detailTextLabel?.text = AppearanceItem.description(of: style);
                    } else {
                        cell.detailTextLabel?.text = AppearanceItem.description(of: .unspecified);
                    }
                }
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
            case .experimental:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ExperimentalSettingsViewCell", for: indexPath);
                cell.accessoryType = .disclosureIndicator;
                return cell;
            case .about:
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
                alert.addAction(UIAlertAction(title: "Create new", style: .default, handler: { (action) in
                    self.showAddAccount(register: true);
                }));
                alert.addAction(UIAlertAction(title: "Add existing", style: .default, handler: { (action) in
                    self.showAddAccount(register: false);
                }));
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
                alert.popoverPresentationController?.sourceView = self.tableView;
                alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

                self.present(alert, animated: true, completion: nil);
            } else {
                // show edit account dialog
                let account = accounts[indexPath.row];
                let accountSettingsController = AccountSettingsViewController.instantiate(fromAppStoryboard: .Account);
                accountSettingsController.hidesBottomBarWhenPushed = true;
                accountSettingsController.account = BareJID(account);
                self.navigationController?.pushViewController(accountSettingsController, animated: true);
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                let alert = UIAlertController(title: "Select status", message: nil, preferredStyle: .actionSheet);
                [nil, "chat", "online", "away", "xa", "dnd"].forEach { (type)->Void in
                    let name = type == nil ? "Automatic" : self.statusNames[type!];
                    let action = UIAlertAction(title: name, style: .default) { (a) in
                        Settings.StatusType.setValue(type);
                        self.tableView.reloadData();                        
                    };
                    if type != nil {
                        action.setValue(getStatusIconForActionIcon(named: "presence_\(type!)", size: 36, withBorder: true), forKey: "image")
                    }
                    alert.addAction(action);
                }
            
                let action = UIAlertAction(title: "Cancel", style: .cancel, handler: nil);
                alert.addAction(action);
                
                alert.popoverPresentationController?.sourceView = self.tableView;
                alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);
                
                self.present(alert, animated: true, completion: nil);
            }
            else if indexPath.row == 1 {
                let alert = UIAlertController(title: "Status", message: "Enter status message", preferredStyle: .alert);
                alert.addTextField(configurationHandler: { (textField) in
                    textField.text = Settings.StatusMessage.getString();
                })
                alert.addAction(UIAlertAction(title: "Set", style: .default, handler: { (action) -> Void in
                    Settings.StatusMessage.setValue((alert.textFields![0] as UITextField).text);
                    self.tableView.reloadData();
                }));
                self.present(alert, animated: true, completion: nil);
            }
        } else if indexPath.section == 2 {
            switch SettingsGroup.groups[indexPath.row] {
            case .appearance:
                if #available(iOS 13.0, *) {
                let controller = TablePickerViewController(style: .grouped);
                let values: [UIUserInterfaceStyle] = [.unspecified, .light, .dark];
                controller.selected = values.firstIndex(of: self.view.window?.overrideUserInterfaceStyle ?? .unspecified) ?? 0;
                controller.items = values.map({ (it)->TablePickerViewItemsProtocol in
                    return AppearanceItem(value: it);
                });
                controller.onSelectionChange = { (_item) -> Void in
                    let item = _item as! AppearanceItem;
                    for window in UIApplication.shared.windows {
                        window.overrideUserInterfaceStyle = item.value;
                    }
                    switch item.value {
                    case .dark:
                        Settings.appearance.setValue("dark")
                    case .light:
                        Settings.appearance.setValue("light")
                    case .unspecified:
                        Settings.appearance.setValue("auto")
                    default:
                        Settings.appearance.setValue("auto")
                    }
                    self.tableView.reloadData();
                };
                self.navigationController?.pushViewController(controller, animated: true);
                }
            default:
                break;
            }
        }
    }
    
    @available(iOS 13.0, *)
    class AppearanceItem: TablePickerViewItemsProtocol {
    
    public static func description(of value: UIUserInterfaceStyle) -> String {
        switch value {
        case .unspecified:
            return "Auto";
        case .light:
            return "Light";
        case .dark:
            return "Dark";
        default:
            return "Auto";
        }
    }
    
    let description: String;
    let value: UIUserInterfaceStyle;
    
    init(value: UIUserInterfaceStyle) {
        self.value = value;
        self.description = AppearanceItem.description(of: value);
    }
        
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false;
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            if indexPath.section == 0 {
                let accounts = AccountManager.getAccounts();
                if accounts.count > indexPath.row {
                    let account = accounts[indexPath.row];
                    
                }
            }
        }
    }
        
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        (segue.destination as? UINavigationController)?.visibleViewController?.hidesBottomBarWhenPushed = true;
    }
        
    @objc func accountStateChanged(_ notification: Notification) {
        DispatchQueue.main.async() {
            self.tableView.reloadData();
        }
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
    
    fileprivate func getStatusIconForActionIcon(named: String, size: Int, withBorder: Bool) -> UIImage? {
        guard var image = UIImage(named: named) else {
            return nil;
        }
        
        let boxSize = CGSize(width: size, height: size);
        let imageSize = CGSize(width: (size*2)/3, height: (size*2)/3);
        
        let imageRect = CGRect(origin: CGPoint(x: (boxSize.width - imageSize.width)/2, y: (boxSize.height - imageSize.height)/2), size: imageSize);
        
        UIGraphicsBeginImageContextWithOptions(boxSize, false, 0);
        if withBorder {
            let ctx = UIGraphicsGetCurrentContext();
            let path = CGPath(ellipseIn: imageRect, transform: nil);
            ctx?.addPath(path);
        
            ctx?.setFillColor(UIColor.white.cgColor);
//        ctx?.fill(imageRect);
            ctx?.fillPath();
        }
        image.draw(in: imageRect);
        image = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        return image.withRenderingMode(.alwaysOriginal);
    }

    fileprivate func getStatusIconForActionIconOld(named: String) -> UIImage? {
        guard var image = UIImage(named: named) else {
            return nil;
        }
        let newSize = CGSize(width: image.size.width * 1.5, height: image.size.height * 1.5);
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0);
        let ctx = UIGraphicsGetCurrentContext();
        ctx?.setFillColor(UIColor.white.cgColor);
        ctx?.fill(CGRect(origin: .zero, size: newSize));
        image.draw(in: CGRect(origin: CGPoint(x: image.size.width * 0.25, y: image.size.height * 0.25), size: image.size));
        image = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        return image.withRenderingMode(.alwaysOriginal);
    }
 
    @IBAction func closeClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }
    
    enum SettingsGroup {
        case appearance
        case chat
        case contacts
        case notifications
        case experimental
        case about
        
        static let groups: [SettingsGroup] = {
            if #available(iOS 13.0, *) {
                return [.appearance, .chat, .contacts, .notifications, .experimental, .about]
            } else {
                return [.chat, .contacts, .notifications, .experimental, .about]
            }
        }()
    }
}
