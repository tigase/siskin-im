//
// GetInTouchViewController.swift
//
// Siskin IM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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

class GetInTouchViewController: UITableViewController {

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 1:
                UIApplication.shared.open(URL(string: "https://github.com/tigase/siskin-im")!)
            case 2:
                (UIApplication.shared.delegate as! AppDelegate).open(xmppUri: AppDelegate.XmppUri(jid: JID("tigase@muc.tigase.org"), action: .join, dict: nil), action: .join);
            default:
                UIApplication.shared.open(URL(string: "https://siskin.im")!);
            }
        default:
            switch indexPath.row {
            case 1:
                UIApplication.shared.open(URL(string: "https://twitter.com/tigase")!);
            case 2:
                UIApplication.shared.open(URL(string: "https://fosstodon.org/@tigase")!);
            default:
                UIApplication.shared.open(URL(string: "https://tigase.net")!);
            }
        }
    }
    
}
