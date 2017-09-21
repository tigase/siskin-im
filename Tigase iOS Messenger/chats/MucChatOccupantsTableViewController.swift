//
// MucChatOccupantsTableViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import UIKit
import TigaseSwift

class MucChatOccupantsTableViewController: UITableViewController, EventHandler {
    
    var xmppService:XmppService!;
    
    var account: BareJID!;
    var room: Room!;
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        xmppService.registerEventHandler(self, for: MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE);
    }
    override func viewWillDisappear(_ animated: Bool) {
        xmppService.unregisterEventHandler(self, for: MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE);
        super.viewWillDisappear(animated);
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in: UITableView) -> Int {
        return 1;
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return room.presences.count;
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MucChatOccupantsTableViewCell", for: indexPath as IndexPath) as! MucChatOccupantsTableViewCell;

        let nicknames = Array(room.presences.keys).sorted();
        let nickname = nicknames[indexPath.row];
        let occupant = room.presences[nickname];
        cell.nicknameLabel.text = nickname;
        if occupant?.jid != nil {
            cell.avatarStatusView.setAvatar(xmppService.avatarManager.getAvatar(for: occupant!.jid!.bareJid, account: account));
        } else {
            cell.avatarStatusView.setAvatar(xmppService.avatarManager.defaultAvatar);
        }
        cell.avatarStatusView.setStatus(occupant?.presence.show);
        cell.statusLabel.text = occupant?.presence.status;
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false;
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
    
    func handle(event: Event) {
        switch event {
        case is MucModule.OccupantLeavedEvent, is MucModule.OccupantComesEvent, is MucModule.OccupantChangedPresenceEvent, is MucModule.OccupantChangedNickEvent:
            DispatchQueue.main.async() {
                self.tableView.reloadData();
            }
        default:
            break;
        }
    }

}
