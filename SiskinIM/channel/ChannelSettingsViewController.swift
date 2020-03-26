//
// ChannelSettingsViewController.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

class ChannelSettingsViewController: UITableViewController {
    
    @IBOutlet var channelNameField: UILabel!;
    @IBOutlet var channelAvatarView: AvatarView!
    @IBOutlet var channelDescriptionField: UILabel!;
    @IBOutlet var notificationsField: UILabel!;
        
    
    var channel: DBChannel!;

    private var needRefresh = true;
    
    override func viewWillAppear(_ animated: Bool) {
        channelNameField.text = channel.name ?? channel.channelJid.stringValue;
        channelAvatarView.layer.cornerRadius = channelAvatarView.frame.width / 2;
        channelAvatarView.layer.masksToBounds = true;
//        roomAvatarView.widthAnchor.constraint(equalTo: roomAvatarView.heightAnchor).isActive = true;
        channelAvatarView.set(name: nil, avatar: self.squared(image: AvatarManager.instance.avatar(for: channel.channelJid, on: channel.account)), orDefault: AvatarManager.instance.defaultGroupchatAvatar);
        channelDescriptionField.text = channel.description ?? "";
        
        refresh();
        refreshPermissions();
    }
    
    @IBAction func dismissView() {
        self.dismiss(animated: true, completion: nil);
    }
    
    func refresh() {
        notificationsField.text = NotificationItem(type: channel.options.notifications).description;
        
        guard needRefresh, let client = XmppService.instance.getClient(forJid: channel.account), let mixModule: MixModule = client.modulesManager.getModule(MixModule.ID) else {
            return;
        }
        operationStarted(message: "Checking...");
        
        let channel = self.channel!;
        let dispatchGroup = DispatchGroup();
        if channel.permissions == nil {
            dispatchGroup.enter();
            mixModule.retrieveAffiliations(for: channel, completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    self?.refreshPermissions();
                }
                dispatchGroup.leave();
            })
        }
        dispatchGroup.enter();
        mixModule.retrieveAvatar(for: channel.channelJid, completionHandler: { result in
            switch result {
            case .success(let avatarInfo):
                if !AvatarManager.instance.hasAvatar(withHash: avatarInfo.id) {
                    AvatarManager.instance.retrievePepUserAvatar(for: channel.channelJid, on: channel.account, hash: avatarInfo.id);
                }
            case .failure(_):
                break;
            }
            dispatchGroup.leave();
        })
        dispatchGroup.notify(queue: DispatchQueue.main, execute: self.operationEnded);
    }
    
    func refreshPermissions() {
        editButtonItem.isEnabled = !(channel?.permissions?.isEmpty ?? true);
        tableView.reloadData();
    }
    
    func operationStarted(message: String) {
        self.tableView.refreshControl = UIRefreshControl();
        self.tableView.refreshControl?.attributedTitle = NSAttributedString(string: message);
        self.tableView.refreshControl?.isHidden = false;
        self.tableView.refreshControl?.layoutIfNeeded();
        self.tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y - self.tableView.refreshControl!.frame.height), animated: true)
        self.tableView.refreshControl?.beginRefreshing();
    }
    
    func operationEnded() {
        self.tableView.refreshControl?.endRefreshing();
        self.tableView.refreshControl = nil;
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 3 && !(channel.permissions?.contains(.changeConfig) ?? false) {
            return 0;
        }
        return super.tableView(tableView, numberOfRowsInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        if indexPath.section == 1 && indexPath.row == 0 {
            let controller = TablePickerViewController();
            controller.items = [NotificationItem(type: .always), NotificationItem(type: .mention), NotificationItem(type: .none)];
            controller.selected = controller.items.firstIndex(where: { (item) -> Bool in
                return (item as! NotificationItem).type == channel.options.notifications;
            })!;
            controller.onSelectionChange = { item in
                self.notificationsField.text = item.description;
                
                self.channel.modifyOptions({ (options) in
                    options.notifications = (item as! NotificationItem).type;
                }, completionHandler: nil);
                let account = self.channel.account;
                if let pushModule: SiskinPushNotificationsModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(SiskinPushNotificationsModule.ID), let pushSettings = pushModule.pushSettings {
                    pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                        switch result {
                        case .success(_):
                            break;
                        case .failure(let err):
                            AccountSettings.pushHash(account).set(int: 0);
                        }
                    });
                }
            }
            self.navigationController?.pushViewController(controller, animated: true);
        }
        if indexPath.section == 3 && indexPath.row == 0, let channel = self.channel {
            let alertController = UIAlertController(title: "Delete channel?", message: "All messages will be deleted and all participants will be kicked out. Are you sure?", preferredStyle: .actionSheet);
            alertController.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { action in
                guard let mixModule: MixModule = XmppService.instance.getClient(for: channel.account)?.modulesManager.getModule(MixModule.ID) else {
                    return;
                }
                // -- handle this properly!!
                mixModule.destroy(channel: channel.channelJid, completionHandler: { [weak self] result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(_):
                            self?.dismiss(animated: true, completion: nil);
                        case .failure(let errorCondition):
                            guard let that = self else {
                                return;
                            }
                            let alert = UIAlertController(title: "Channel destruction failed!", message: "It was not possible to destroy channel \(channel.name ?? channel.channelJid.stringValue). Server returned an error: \(errorCondition.rawValue)", preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                            that.present(alert, animated: true, completion: nil);
                        }
                    }
                });
            }));
            alertController.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
            alertController.popoverPresentationController?.sourceView = self.tableView;
            alertController.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);
            self.present(alertController, animated: true, completion: nil);
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "chatShowAttachments" {
            if let attachmentsController = segue.destination as? ChatAttachmentsController {
                attachmentsController.account = self.channel.account;
                attachmentsController.jid = self.channel.channelJid;
            }
        }
        if let destination = segue.destination as? ChannelEditInfoController {
            destination.channel = self.channel;
        }
    }
    
    @IBAction func editClicked(_ sender: UIBarButtonItem) {
        if channel.permissions?.contains(.changeInfo) ?? false {
            self.performSegue(withIdentifier: "editChannelInfo", sender: self);
        }
    }
    
    private func squared(image inImage: UIImage?) -> UIImage? {
        guard let image = inImage else {
            return nil;
        }
        let origSize = image.size;
        guard origSize.width != origSize.height else {
            return image;
        }
        
        let size = min(origSize.width, origSize.height);
        
        let x = origSize.width > origSize.height ? ((origSize.width - origSize.height)/2) : 0.0;
        let y = origSize.width > origSize.height ? 0.0 : ((origSize.height - origSize.width)/2);
        
        print("x:", x, "y:", y, "size:", size, "orig:", origSize);
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0);
        image.draw(in: CGRect(x: x * (-1.0), y: y * (-1.0), width: origSize.width, height: origSize.height));
        let squared = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return squared;
    }
    
    class NotificationItem: TablePickerViewItemsProtocol {
        
        let type: ConversationNotification;
        
        var description: String {
            get {
                switch type {
                case .none:
                    return "Muted";
                case .mention:
                    return "When mentioned";
                case .always:
                    return "Always";
                }
            }
        }
        
        init(type: ConversationNotification) {
            self.type = type;
        }
        
    }
}
