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
import Martin
import Combine
import Shared

class ChannelSettingsViewController: UITableViewController {
    
    @IBOutlet var channelNameField: UILabel!;
    @IBOutlet var channelAvatarView: AvatarView!
    @IBOutlet var channelDescriptionField: UILabel!;
    @IBOutlet var notificationsField: UILabel!;
        
    var channel: Channel!;

    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewWillAppear(_ animated: Bool) {
        channel.displayNamePublisher.map({ $0 }).assign(to: \.text, on: channelNameField!).store(in: &cancellables);
        channelAvatarView.layer.cornerRadius = channelAvatarView.frame.width / 2;
        channelAvatarView.layer.masksToBounds = true;
        channel.avatarPublisher.replaceNil(with: AvatarManager.instance.defaultGroupchatAvatar).assign(to: \.avatar, on: channelAvatarView).store(in: &cancellables);
        channel.descriptionPublisher.assign(to: \.text, on: channelDescriptionField).store(in: &cancellables);
        channel.optionsPublisher.map({ ChannelSettingsViewController.labelFor(conversationNotification: $0.notifications) as String? }).assign(to: \.text, on: notificationsField!).store(in: &cancellables);
        
        refresh();
        refreshPermissions();
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.cancellables.removeAll();
        super.viewDidDisappear(animated)
    }
    
    @IBAction func dismissView() {
        self.dismiss(animated: true, completion: nil);
    }
    
    func refresh() {
        guard let mixModule = channel.context?.module(.mix) else {
            return;
        }
        operationStarted(message: NSLocalizedString("Checking…", comment: "channel settings view opeartion label"));
        
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
        navigationItem.rightBarButtonItem?.isEnabled = channel.permissions?.contains(.changeInfo) ?? false;
        editButtonItem.isEnabled = channel.permissions?.contains(.changeInfo) ?? false;
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
            let controller = TablePickerViewController<ConversationNotification>(options: [.always, .mention, .none], value: channel.options.notifications, labelFn: ChannelSettingsViewController.labelFor(conversationNotification: ));

            controller.sink(receiveValue: { [weak self] value in
                self?.channel.updateOptions({ options in
                    options.notifications = value;
                }, completionHandler: {
                    if let account = self?.channel.account, let pushModule = self?.channel.context?.module(.push) as? SiskinPushNotificationsModule, let pushSettings = pushModule.pushSettings {
                        pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                            switch result {
                            case .success(_):
                                break;
                            case .failure(_):
                                AccountSettings.pushHash(for: account, value: 0);
                            }
                        });
                    }
                })
            });
            self.navigationController?.pushViewController(controller, animated: true);
        }
        if indexPath.section == 3 && indexPath.row == 0, let channel = self.channel {
            let alertController = UIAlertController(title: NSLocalizedString("Delete channel?", comment: "alert title"), message: NSLocalizedString("All messages will be deleted and all participants will be kicked out. Are you sure?", comment: "alert body"), preferredStyle: .actionSheet);
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .destructive, handler: { action in
                guard let mixModule = channel.context?.module(.mix) else {
                    return;
                }
                // -- handle this properly!!
                mixModule.destroy(channel: channel.channelJid, completionHandler: { [weak self] result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(_):
                            self?.dismiss(animated: true, completion: nil);
                        case .failure(let error):
                            guard let that = self else {
                                return;
                            }
                            let alert = UIAlertController(title: NSLocalizedString("Channel destruction failed!", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to destroy channel %@. Server returned an error: %@", comment: "alert body"), channel.name ?? channel.channelJid.stringValue, error.localizedDescription), preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                            that.present(alert, animated: true, completion: nil);
                        }
                    }
                });
            }));
            alertController.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .cancel, handler: nil));
            alertController.popoverPresentationController?.sourceView = self.tableView;
            alertController.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);
            self.present(alertController, animated: true, completion: nil);
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "chatShowAttachments" {
            if let attachmentsController = segue.destination as? ChatAttachmentsController {
                attachmentsController.conversation = self.channel;
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
    
    static func labelFor(conversationNotification type: ConversationNotification) -> String {
        switch type {
        case .none:
            return NSLocalizedString("Muted", comment: "conversation notifications status");
        case .mention:
            return NSLocalizedString("When mentioned", comment: "conversation notifications status");
        case .always:
            return NSLocalizedString("Always", comment: "conversation notifications status");
        }
    }
    
}
