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
    
    var xmppService:XmppService! {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    var account: BareJID!;
    var room: Room!;
    
    override func viewDidLoad() {
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

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        xmppService.registerEventHandler(self, events: MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE);
    }
    override func viewWillDisappear(animated: Bool) {
        xmppService.unregisterEventHandler(self, events: MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE);
        super.viewWillDisappear(animated);
    }
    
    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1;
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return room.presences.count;
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("MucChatOccupantsTableViewCell", forIndexPath: indexPath) as! MucChatOccupantsTableViewCell;

        let nicknames = Array(room.presences.keys).sort();
        let nickname = nicknames[indexPath.row];
        let occupant = room.presences[nickname];
        cell.nicknameLabel.text = nickname;
        if occupant?.jid != nil {
            cell.avatarStatusView.setAvatar(xmppService.avatarManager.getAvatar(occupant!.jid!.bareJid, account: account));
        } else {
            cell.avatarStatusView.setAvatar(xmppService.avatarManager.defaultAvatar);
        }
        cell.avatarStatusView.setStatus(occupant?.presence.show);
        cell.statusLabel.text = occupant?.presence.status;
        
        return cell
    }
    
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
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
    
    func handleEvent(event: Event) {
        switch event {
        case is MucModule.OccupantLeavedEvent, is MucModule.OccupantComesEvent, is MucModule.OccupantChangedPresenceEvent, is MucModule.OccupantChangedNickEvent:
            dispatch_async(dispatch_get_main_queue()) {
                self.tableView.reloadData();
            }
        default:
            break;
        }
    }

}
