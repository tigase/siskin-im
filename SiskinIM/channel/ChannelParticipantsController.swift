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
import Martin
import Combine

class ChannelParticipantsController: UITableViewController {
    
    var channel: Channel!;
    
    private var participants: [MixParticipant] = [];
    private var invitationOnly: Bool = false;
    
    private var dispatcher = QueueDispatcher(label: "ChannelParticipantsController");
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        channel.participantsPublisher.throttle(for: 0.2, scheduler: dispatcher.queue, latest: true).sink(receiveValue: { [weak self] participants in
            self?.update(participants: participants);
        }).store(in: &cancellables);
        if channel.permissions?.contains(.changeConfig) ?? false, let mixModule = channel.context?.module(.mix) {
            self.operationStarted(message: NSLocalizedString("Refreshing…", comment: "channel participants view operation"));
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
                    case .failure(_):
                        break;
                    }
                    self?.operationEnded();
                }
            });
        }
    }
        
    override func viewDidDisappear(_ animated: Bool) {
        cancellables.removeAll();
        super.viewDidDisappear(animated);
    }
    
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return participants.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let participant = self.participants[indexPath.row];
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChannelParticipantTableViewCell", for: indexPath) as! ChannelParticipantTableViewCell;
        cell.set(participant: participant, in: channel);
        return cell;
    }
    
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
            let block = UIAction(title: NSLocalizedString("Block participant", comment: "action"), image: UIImage(systemName: "hand.raised.fill"), handler: { action in
                guard let mixModule = self.channel.context?.module(.mix) else {
                    return;
                }
                
                self.operationStarted(message: NSLocalizedString("Blocking…", comment: "channel participants view operation"));
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
    
    private func update(participants: [MixParticipant]) {
        let oldParticipants = self.participants;
        let newParticipants = participants.sorted(by: { (p1,p2) -> Bool in
            return (p1.nickname ?? p1.id).caseInsensitiveCompare(p2.nickname ?? p2.id) == .orderedAscending;
        });
        let changes = newParticipants.calculateChanges(from: oldParticipants);
        DispatchQueue.main.sync {
            self.participants = newParticipants;
            self.tableView?.beginUpdates();
            self.tableView?.deleteRows(at: changes.removed.map({ IndexPath(row: $0, section: 0)}), with: .fade);
            self.tableView?.insertRows(at: changes.inserted.map({ IndexPath(row: $0, section: 0)}), with: .fade);
            self.tableView?.endUpdates();
        }
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

class ChannelParticipantTableViewCell: UITableViewCell {
    
    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var labelView: UILabel!;
    @IBOutlet var jidView: UILabel!;
    
    static func labelViewFont() -> UIFont {
        let preferredFont = UIFont.preferredFont(forTextStyle: .subheadline);
        let fontDescription = preferredFont.fontDescriptor.withSymbolicTraits(.traitBold)!;
        return UIFont(descriptor: fontDescription, size: preferredFont.pointSize);
    }
    
    func set(participant: MixParticipant, in channel: Channel) {
        let jid = participant.jid ?? BareJID(localPart: "\(participant.id)#\(channel.channelJid.localPart!)", domain: channel.channelJid.domain);
        avatarView?.set(name: participant.nickname ?? participant.id, avatar: AvatarManager.instance.avatar(for: jid, on: channel.account));
        
        labelView.font = ChannelParticipantTableViewCell.labelViewFont();
        labelView?.text = participant.nickname;
        jidView?.text = participant.jid?.stringValue ?? participant.id
    }
    
}
