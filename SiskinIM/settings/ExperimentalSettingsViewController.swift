//
// ExperimentalSettingsViewController.swift
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

class ExperimentalSettingsViewController: UITableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 5;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = SettingsEnum(rawValue: indexPath.row)!;
        switch setting {
        case .notificationsFromUnknown:
            let cell = tableView.dequeueReusableCell(withIdentifier: "XmppPipeliningTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.XmppPipelining.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.XmppPipelining.setValue(switchView.isOn);
            }
            return cell;
        case .enableBookmarksSync:
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnableBookmarksSyncTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.enableBookmarksSync.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.enableBookmarksSync.setValue(switchView.isOn);
            }
            return cell;
        case .enableMarkdown:
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnableMarkdownTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.EnableMarkdownFormatting.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.EnableMarkdownFormatting.setValue(switchView.isOn);
                if !switchView.isOn {
                    Settings.ShowEmoticons.setValue(false);
                }
                self.tableView.reloadData();
            }
            return cell;
        case .showEmoticons:
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnableEmoticonsTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.ShowEmoticons.getBool();
            cell.switchView.isEnabled = Settings.EnableMarkdownFormatting.getBool();
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.ShowEmoticons.setValue(switchView.isOn);
            }
            return cell;
        case .usePublicStinServers:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PublicStunServersTableViewCell", for: indexPath) as! SwitchTableViewCell;
            cell.switchView.isOn = Settings.usePublicStunServers.getBool();
            cell.switchView.isEnabled = true;
            cell.valueChangedListener = {(switchView: UISwitch) in
                Settings.usePublicStunServers.setValue(switchView.isOn);
            }
            return cell;
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true);
    }
    
    internal enum SettingsEnum: Int {
        case notificationsFromUnknown = 0
        case enableBookmarksSync = 1
        case enableMarkdown = 2
        case showEmoticons = 3
        case usePublicStinServers = 4
    }
}
