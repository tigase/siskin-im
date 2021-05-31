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
import TigaseSwift
import Combine

class MucChatOccupantsTableViewController: UITableViewController {
    
    private var dispatcher = QueueDispatcher(label: "MucChatOccupantsTableViewController");
    
    var room: Room! {
        didSet {
            cancellables.removeAll();
            room.occupantsPublisher.receive(on: self.dispatcher.queue).sink(receiveValue: { [weak self] value in
                self?.update(participants: value);
            }).store(in: &cancellables);
        }
    }
    
    var mentionOccupant: ((String)->Void)? = nil;
    
    private var cancellables: Set<AnyCancellable> = [];
    private var participants: [MucOccupant] = [];
    
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
        let oldParticipants = self.participants;
        let newParticipants = participants.sorted(by: { (i1,i2) -> Bool in i1.nickname.lowercased() < i2.nickname.lowercased() });
        let changes = newParticipants.calculateChanges(from: oldParticipants);
            
        DispatchQueue.main.sync {
            self.participants = newParticipants;
            self.tableView?.beginUpdates();
            self.tableView?.deleteRows(at: changes.removed.map({ IndexPath(row: $0, section: 0)}), with: .fade);
            self.tableView?.insertRows(at: changes.inserted.map({ IndexPath(row: $0, section: 0)}), with: .fade);
            self.tableView?.endUpdates();
            self.tableView?.isHidden = false;
        }
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in: UITableView) -> Int {
        return 1;
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return participants.count;
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MucChatOccupantsTableViewCell", for: indexPath as IndexPath) as! MucChatOccupantsTableViewCell;
        
        let occupant = participants[indexPath.row];
        cell.set(occupant: occupant, in: self.room);
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        let occupant = participants[indexPath.row];

        if let fn = mentionOccupant {
            fn(occupant.nickname);
        }
        self.navigationController?.popViewController(animated: true);
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard room.state == .joined else {
            return nil;
        }
        
        let participant = self.participants[indexPath.row];
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
            var actions: [UIAction] = [];
            actions.append(UIAction(title: "Private message", handler: { action in
                let alert = UIAlertController(title: "Send message", message: "Enter message to send to: \(participant.nickname)", preferredStyle: .alert);
                alert.addTextField(configurationHandler: nil);
                alert.addAction(UIAlertAction(title: "Send", style: .default, handler: { action in
                    guard let text = alert.textFields?.first?.text else {
                        return;
                    }
                    self.room.sendPrivateMessage(to: participant, text: text);
                }));
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
                self.present(alert, animated: true, completion: nil);
            }));
            if let jid = participant.jid, self.room.affiliation == MucAffiliation.admin {
                actions.append(UIAction(title: "Ban user", handler: { action in
                    guard let mucModule = self.room.context?.module(.muc) else {
                        return;
                    }
                    let alert = UIAlertController(title: "Banning user", message: "Do you want to ban user \(participant.nickname)?", preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { action in
                        mucModule.setRoomAffiliations(to: self.room, changedAffiliations: [MucModule.RoomAffiliation(jid: jid, affiliation: .outcast)], completionHandler: { result in
                            switch result {
                            case .success(_):
                                break;
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(title: "Banning user \(participant.nickname) failed", message: "Server returned an error: \(error)", preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                                    self.present(alert, animated: true, completion: nil);
                                }
                            }
                        });
                    }))
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
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
