//
// ContactBasicTableViewCell.swift
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

class ContactBasicTableViewCell: UITableViewCell {

    @IBOutlet var avatarView: UIImageView!
    @IBOutlet var nameView: UILabel!
    @IBOutlet var companyView: UILabel!
    @IBOutlet var jidView: UILabel!;
    @IBOutlet var accountView: UILabel!;
    
    var account: BareJID!;
    var jid: BareJID!;
    var vcard: VCard? {
        didSet {
            var fn = vcard?.fn;
            if fn == nil {
                if let given = vcard?.givenName, let surname = vcard?.surname {
                    fn = "\(given) \(surname)";
                }
            }
            nameView.text = fn ?? jid.stringValue;
            
            let org = vcard?.organizations.first?.name;
            let role = vcard?.role;
            
            if org != nil && role != nil {
                companyView.text = "\(role!) at \(org!)";
            } else {
                companyView.text = org ?? role;
            }
            
            avatarView.image = AvatarManager.instance.avatar(for: jid, on: account) ?? AvatarManager.instance.defaultAvatar;
            jidView.text = jid.stringValue;
            accountView.text = String.localizedStringWithFormat(NSLocalizedString("using %@", comment: "account info label"), account.stringValue);
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
