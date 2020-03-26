//
// ChannelParticipantsController.swift
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

class ChannelParticipantsController: UITableViewController {
    
    var channel: DBChannel!;
    
    private var participants: [MixParticipant] = [];
    private var invitationOnly: Bool = false;
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        NotificationCenter.default.addObserver(self, selector: #selector(participantsChanged(_:)), name: MixEventHandler.PARTICIPANTS_CHANGED, object: channel);
        refreshParticipants();
        if #available(iOS 13.0, *), channel.permissions?.contains(.changeConfig) ?? false, let mixModule: MixModule = XmppService.instance.getClient(for: self.channel.account)?.modulesManager.getModule(MixModule.ID) {
            self.operationStarted(message: "Refreshing...");
            mixModule.checkAccessPolicy(of: channel.channelJid, completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let invitiationOnly):
                        if let that = self {
                            that.invitationOnly = invitiationOnly;
                            if invitiationOnly {
                                that.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: that, action: #selector(that.inviteToChannel(_:)));
                            } else {
                                that.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: that, action: #selector(that.manageBlocked(_:)));
                            }
                        }
                    case .failure(let error):
                        break;
                    }
                    self?.operationEnded();
                }
            });
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated);
        NotificationCenter.default.removeObserver(self, name: MixEventHandler.PARTICIPANTS_CHANGED, object: channel);
    }
    
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return participants.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let participant = self.participants[indexPath.row];
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChannelParticipantVIewCell", for: indexPath);
        let jid = participant.jid ?? BareJID(localPart: "\(participant.id)#\(channel.channelJid.localPart!)", domain: channel.channelJid.domain);
        cell.imageView?.image = AvatarManager.instance.avatar(for: jid, on: channel.account) ?? AvatarManager.instance.defaultAvatar;
        cell.textLabel?.text = participant.nickname;
        cell.detailTextLabel?.text = participant.jid?.stringValue ?? participant.id
        return cell;
    }
    
    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard channel.permissions?.contains(.changeConfig) ?? false else {
            return nil;
        }
        guard let jid = self.participants[indexPath.row].jid else {
            return nil;
        }
        let account = self.channel.account;
        guard account != jid else {
            return nil;
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { actions -> UIMenu? in
            let block = UIAction(title: "Block participant", image: UIImage(systemName: "hand.raised.fill"), handler: { action in
                guard let mixModule: MixModule = XmppService.instance.getClient(for: self.channel.account)?.modulesManager.getModule(MixModule.ID) else {
                    return;
                }
                
                self.operationStarted(message: "Blocking...");
                let channelJid = self.channel.channelJid;
                if self.invitationOnly {
                    mixModule.allowAccess(to: channelJid, for: jid, value: false, completionHandler: { [weak self] result in
                        DispatchQueue.main.async {
                            self?.operationEnded();
                        }
                    });
                } else {
                    mixModule.denyAccess(to: channelJid, for: jid, value: true, completionHandler: { [weak self] result in
                        DispatchQueue.main.async {
                            self?.operationEnded();
                        }
                    });
                }
            });
            return UIMenu(title: "", children: [block]);
        });
    }

    @objc func inviteToChannel(_ sender: Any) {
        self.performSegue(withIdentifier: "showChannelInviteController", sender: self);
    }
    
    @objc func manageBlocked(_ sender: Any) {
        self.performSegue(withIdentifier: "showChannelBlocked", sender: self);
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ChannelInviteController {
            destination.channel = self.channel;
        }
        if let destination = segue.destination as? ChannelBlockedUsersController {
            destination.channel = self.channel;
        }
    }
    
    @objc func participantsChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.refreshParticipants();
        }
    }
    
    private func refreshParticipants() {
        let tmp = Array(channel.participants.values);
        self.participants = tmp.sorted(by: { (p1, p2) -> Bool in
            return (p1.nickname ?? p1.id).caseInsensitiveCompare(p2.nickname ?? p2.id) == .orderedAscending;
        });
        self.tableView.reloadData();
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

}
