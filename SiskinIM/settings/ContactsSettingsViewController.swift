//
// ContactsSettingsViewController.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class ContactsSettingsViewController: CustomTableViewController {
    
    let tree: [[SettingsEnum]] = [
        [SettingsEnum.rosterType, SettingsEnum.rosterDisplayHiddenGroup],
        [SettingsEnum.autoSubscribeOnAcceptedSubscriptionRequest, .blockedContacts],
        ];
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return tree.count;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tree[section].count;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Display"
        case 1:
            return "General";
        default:
            return nil;
        }
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = tree[indexPath.section][indexPath.row];
        switch setting {
        case .rosterType:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RosterTypeTableViewCell", for: indexPath ) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.RosterType.getString() == RosterType.grouped.rawValue;
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.RosterType.setValue((switchView.isOn ? RosterType.grouped : RosterType.flat).rawValue);
            }
            return cell;
        case .rosterDisplayHiddenGroup:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RosterHiddenGroupTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.RosterDisplayHiddenGroup.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.RosterDisplayHiddenGroup.setValue(switchView.isOn);
            }
            return cell;
        case .autoSubscribeOnAcceptedSubscriptionRequest:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AutoSubscribeOnAcceptedSubscriptionRequestTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.AutoSubscribeOnAcceptedSubscriptionRequest.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.AutoSubscribeOnAcceptedSubscriptionRequest.setValue(switchView.isOn);
            }
            return cell;
        case .blockedContacts:
            return tableView.dequeueReusableCell(withIdentifier: "BlockedContactsTableViewCell", for: indexPath);
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
    }
    
    internal enum SettingsEnum: Int {
        case rosterType = 0
        case rosterDisplayHiddenGroup = 1
        case autoSubscribeOnAcceptedSubscriptionRequest = 2
        case blockedContacts = 3
    }
}

