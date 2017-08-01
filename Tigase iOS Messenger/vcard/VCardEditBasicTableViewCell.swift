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

    var xmppService: XmppService {
        let delegate = UIApplication.shared.delegate as! AppDelegate;
        return delegate.xmppService;
    }
    
    @IBOutlet var photoView: UIImageView!
    @IBOutlet var givenNameView: UITextField!
    @IBOutlet var familyNameView: UITextField!
    @IBOutlet var fullNameView: UITextField!
    @IBOutlet var birthdayView: UITextField!
    @IBOutlet var orgView: UITextField!
    @IBOutlet var orgRoleView: UITextField!
    
    var accountJid: BareJID!;
    var avatarManager: AvatarManager!;
    var vcard: VCard! {
        didSet {
            if let photo = vcard.photos.first {
                xmppService.dbVCardsCache.fetchPhoto(photo: photo) { (photoData) in
                    DispatchQueue.main.async {
                        self.photoView.image = ((photoData != nil) ? UIImage(data: photoData!) : nil) ?? self.avatarManager.defaultAvatar;
                    }
                }
            }
            givenNameView.text = vcard.givenName;
            familyNameView.text = vcard.surname;
            fullNameView.text = vcard.fn;
            birthdayView.text = vcard.bday;
            orgView.text = vcard.organizations.first?.name;
            orgRoleView.text = vcard.role;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        let datePicker = UIDatePicker();
        datePicker.datePickerMode = .date;
        datePicker.addTarget(self, action: #selector(VCardEditBasicTableViewCell.bdayValueChanged), for: .valueChanged);
        birthdayView.inputView = datePicker;
        
        givenNameView.delegate = self;
        familyNameView.delegate = self;
        fullNameView.delegate = self;
        orgView.delegate = self;
        orgRoleView.delegate = self;
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func bdayValueChanged(_ sender: UIDatePicker) {
        let formatter = DateFormatter();
        formatter.timeStyle = .none;
        formatter.dateFormat = "yyyy-MM-dd";
        birthdayView.text = formatter.string(from: sender.date);
        vcard.bday = birthdayView.text;
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        let text = textField.text;
        switch textField {
        case givenNameView:
            vcard.givenName = text;
        case familyNameView:
            vcard.surname = text;
        case fullNameView:
            vcard.fn = text;
        case orgView:
            if text != nil {
                vcard.organizations = [VCard.Organization(name: text!)];
            } else {
                vcard.organizations = [];
            }
        case orgRoleView:
            vcard.role = text;
        default:
            break;
        }
    }

}
