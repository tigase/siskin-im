//
// MucChatOccupantsTableViewController.swift
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

class MucChatOccupantsTableViewController: UITableViewController {
    
    private class ParticipantsGroup: Equatable, Hashable {
        static func == (lhs: ParticipantsGroup, rhs: ParticipantsGroup) -> Bool {
            return lhs.role == rhs.role;
        }
        
        let role: MucRole;
        var participants: [MucOccupant];
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(role);
        }
        
        @available(iOS 13.0, *)
        var image: UIImage? {
            switch role {
            case .moderator:
                return UIImage(systemName: "rosette");
            case .participant:
                return UIImage(systemName: "person.3");
            case .visitor:
                return UIImage(systemName: "theatermasks");
            case .none:
                return nil;
            }
        }
        
        var label: String {
            switch role {
            case .moderator:
                return NSLocalizedString("Moderators", comment: "list of users with this role");
            case .participant:
                return NSLocalizedString("Participants", comment: "list of users with this role");
            case .visitor:
                return NSLocalizedString("Visitors", comment: "list of users with this role");
            case .none:
                return NSLocalizedString("None", comment: "list of users with this role");
            }
        }
        
        var labelAttributedString: NSAttributedString {
            if #available(macOS 11.0, *) {
                let text = NSMutableAttributedString(string: "");
                if let image = self.image {
                    let att = NSTextAttachment();
                    att.image = image;
                    text.append(NSAttributedString(attachment: att));
                }
                text.append(NSAttributedString(string: self.label.uppercased()));
                return text;
            } else {
                return NSAttributedString(string: self.label);
            }
        }
        
        init(role: MucRole, participants: [MucOccupant] = []) {
            self.role = role;
            self.participants = participants;
        }
    }
    
    private var dispatcher = QueueDispatcher(label: "MucChatOccupantsTableViewController");
    
    var room: Room! {
        didSet {
            cancellables.removeAll();
            room.occupantsPublisher.throttle(for: 0.1, scheduler: self.dispatcher.queue, latest: true).sink(receiveValue: { [weak self] value in
                self?.update(participants: value);
            }).store(in: &cancellables);
        }
    }
    
    var mentionOccupant: ((String)->Void)? = nil;
    
    private var cancellables: Set<AnyCancellable> = [];
    private let allGroups: [MucRole: ParticipantsGroup] = [
        .moderator: ParticipantsGroup(role: .moderator),
        .participant: ParticipantsGroup(role: .participant),
        .visitor: ParticipantsGroup(role: .visitor)
    ];
    private var groups: [ParticipantsGroup] = [
    ];
    private let allRoles: [MucRole] = [.moderator, .participant, .visitor];

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
    }
    
    private func update(participants: [MucOccupant]) {
        let oldGroups = self.groups;
        let newGroups = allRoles.map({ role in ParticipantsGroup(role: role, participants: participants.filter({ $0.role == role }).sorted(by: { (i1,i2) -> Bool in i1.nickname.lowercased() < i2.nickname.lowercased() })) }).filter({ !$0.participants.isEmpty });

        let allChanges = newGroups.calculateChanges(from: oldGroups);
//
        let allChanges2 = newGroups.compactMap({ newGroup -> (ParticipantsGroup,ParticipantsGroup)? in
            guard let oldGroup = oldGroups.first(where: { $0.role == newGroup.role }) else {
                return nil;
            }
            return (oldGroup, newGroup);
        }).map({ (old, new) in
            return new.participants.calculateChanges(from: old.participants);
        })

        
//        let oldParticipants = self.participants;
//        let newParticipants = participants.sorted(by: { (i1,i2) -> Bool in i1.nickname.lowercased() < i2.nickname.lowercased() });
//        let changes = newParticipants.calculateChanges(from: oldParticipants);
            
        DispatchQueue.main.sync {
            //self.groups = newGroups;

            self.groups = newGroups.map({ newGroup in
                let group = allGroups[newGroup.role]!;
                group.participants = newGroup.participants;
                return group;
            })
            
            self.tableView?.beginUpdates();

            if !allChanges.removed.isEmpty {
                tableView.deleteSections(allChanges.removed, with: .fade);
            }
            
            for (idx, changes) in allChanges2.enumerated() {
                self.tableView.deleteRows(at: changes.removed.map({ [idx, $0 ]}), with: .fade);
                self.tableView.insertRows(at: changes.inserted.map({ [idx, $0 ]}), with: .fade);
            }

            if !allChanges.inserted.isEmpty {
                tableView.insertSections(allChanges.inserted, with: .fade);
            }

//            self.tableView?.deleteRows(at: changes.removed.map({ IndexPath(row: $0, section: 0)}), with: .fade);
//            self.tableView?.insertRows(at: changes.inserted.map({ IndexPath(row: $0, section: 0)}), with: .fade);
            self.tableView?.endUpdates();
            self.tableView?.isHidden = false;
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in: UITableView) -> Int {
        return groups.count;
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return groups[section].participants.count;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return groups[section].label;
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return nil;
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MucChatOccupantsTableViewCell", for: indexPath as IndexPath) as! MucChatOccupantsTableViewCell;
        
        let occupant = groups[indexPath.section].participants[indexPath.row];
        cell.set(occupant: occupant, in: self.room);
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        let occupant = groups[indexPath.section].participants[indexPath.row];

        if let fn = mentionOccupant {
            fn(occupant.nickname);
        }
        self.navigationController?.popViewController(animated: true);
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard room.state == .joined else {
            return nil;
        }
        
        let participant = groups[indexPath.section].participants[indexPath.row];
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
            var actions: [UIAction] = [];
            actions.append(UIAction(title: NSLocalizedString("Private message", comment: "action label"), handler: { action in
                let alert = UIAlertController(title: NSLocalizedString("Send message", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Enter message to send to: %@", comment: "alert body"), participant.nickname), preferredStyle: .alert);
                alert.addTextField(configurationHandler: nil);
                alert.addAction(UIAlertAction(title: NSLocalizedString("Send", comment: "button label"), style: .default, handler: { action in
                    guard let text = alert.textFields?.first?.text else {
                        return;
                    }
                    self.room.sendPrivateMessage(to: participant, text: text);
                }));
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
                self.present(alert, animated: true, completion: nil);
            }));
            if let jid = participant.jid, self.room.affiliation == MucAffiliation.admin {
                actions.append(UIAction(title: NSLocalizedString("Ban user", comment: "action label"), handler: { action in
                    guard let mucModule = self.room.context?.module(.muc) else {
                        return;
                    }
                    let alert = UIAlertController(title: NSLocalizedString("Banning user", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Do you want to ban user %@?", comment: "alert body"), participant.nickname), preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { action in
                        mucModule.setRoomAffiliations(to: self.room, changedAffiliations: [MucModule.RoomAffiliation(jid: jid, affiliation: .outcast)], completionHandler: { result in
                            switch result {
                            case .success(_):
                                break;
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(title: String.localizedStringWithFormat(NSLocalizedString("Banning user %@ failed", comment: "alert title"), participant.nickname), message: String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .cancel, handler: nil));
                                    self.present(alert, animated: true, completion: nil);
                                }
                            }
                        });
                    }))
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
                    self.present(alert, animated: true, completion: nil);
                }));
            }
            return UIMenu(title: "", children: actions);
        });
    }

    /*
    // Override to support editing the table view.
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let invitationController = segue.destination as? InviteViewController ?? (segue.destination as? UINavigationController)?.visibleViewController as? InviteViewController {
            invitationController.room = self.room;
        }
    }

}
