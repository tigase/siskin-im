//
// ChannelSelectNewOwnerViewController.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

class ChannelSelectNewOwnerViewController: UITableViewController {
    
    @IBOutlet var confirmBtn: UIBarButtonItem!;
    
    var participants: [MixParticipant] = [];
    var channel: Channel! = nil;
    
    var selected: MixParticipant? {
        didSet {
            confirmBtn.isEnabled = selected != nil;
        }
    }
    
    var completionHandler: ((MixParticipant?)->Void)?;
    
    @IBAction func cancelTapped(_ sender: Any) {
        self.navigationController?.dismiss(animated: true);
    }
    
    @IBAction func doneTapped(_ sender: Any) {
        completionHandler?(selected);
        self.navigationController?.dismiss(animated: true);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return participants.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChannelParticipantTableViewCell", for: indexPath) as! ChannelParticipantTableViewCell;
        
        cell.set(participant: participants[indexPath.row], in: channel);
        
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selected = participants[indexPath.row];
    }
    
}
