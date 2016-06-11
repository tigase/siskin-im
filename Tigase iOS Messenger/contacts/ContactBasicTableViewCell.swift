//
// ContactBasicTableViewCell.swift
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

class ContactBasicTableViewCell: UITableViewCell {

    @IBOutlet var avatarView: UIImageView!
    @IBOutlet var nameView: UILabel!
    @IBOutlet var companyView: UILabel!
    
    var avatarManager: AvatarManager!;
    var account: BareJID!;
    var jid: BareJID!;
    var vcard: VCardModule.VCard? {
        didSet {
            var fn = vcard?.fn;
            if fn == nil {
                if let given = vcard?.givenName, let family = vcard?.familyName {
                    fn = "\(given) \(family)";
                }
            }
            nameView.text = fn ?? jid.stringValue;
            
            let org = vcard?.orgName;
            let role = vcard?.role;
            
            if org != nil && role != nil {
                companyView.text = "\(role!) at \(org!)";
            } else {
                companyView.text = org ?? role;
            }
            
            avatarView.image = avatarManager.getAvatar(jid, account: account);
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
