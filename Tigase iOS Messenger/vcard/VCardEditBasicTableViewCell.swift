//
// VCardEditBasicTableViewCell.swift
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

class VCardEditBasicTableViewCell: UITableViewCell, UITextFieldDelegate {

    @IBOutlet var photoView: UIImageView!
    @IBOutlet var givenNameView: UITextField!
    @IBOutlet var familyNameView: UITextField!
    @IBOutlet var fullNameView: UITextField!
    @IBOutlet var birthdayView: UITextField!
    @IBOutlet var orgView: UITextField!
    @IBOutlet var orgRoleView: UITextField!
    
    var accountJid: BareJID!;
    var avatarManager: AvatarManager!;
    var vcard: VCardModule.VCard! {
        didSet {
            let photoData = vcard.photoValBinary;
            photoView.image = ((photoData != nil) ? UIImage(data: photoData!) : nil) ?? avatarManager.defaultAvatar;
            givenNameView.text = vcard.givenName;
            familyNameView.text = vcard.familyName;
            fullNameView.text = vcard.fn;
            birthdayView.text = vcard.bday;
            orgView.text = vcard.orgName;
            orgRoleView.text = vcard.role;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        let datePicker = UIDatePicker();
        datePicker.datePickerMode = .Date;
        datePicker.addTarget(self, action: #selector(VCardEditBasicTableViewCell.bdayValueChanged), forControlEvents: .ValueChanged);
        birthdayView.inputView = datePicker;
        
        givenNameView.delegate = self;
        familyNameView.delegate = self;
        fullNameView.delegate = self;
        orgView.delegate = self;
        orgRoleView.delegate = self;
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func bdayValueChanged(sender: UIDatePicker) {
        let formatter = NSDateFormatter();
        formatter.timeStyle = .NoStyle;
        formatter.dateFormat = "yyyy-MM-dd";
        birthdayView.text = formatter.stringFromDate(sender.date);
        vcard.bday = birthdayView.text;
    }
    
    func textFieldDidEndEditing(textField: UITextField) {
        let text = textField.text;
        switch textField {
        case givenNameView:
            vcard.givenName = text;
        case familyNameView:
            vcard.familyName = text;
        case fullNameView:
            vcard.fn = text;
        case orgView:
            vcard.orgName = text;
        case orgRoleView:
            vcard.role = text;
        default:
            break;
        }
    }

}
