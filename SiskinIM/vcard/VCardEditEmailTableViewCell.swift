//
// VCardEditEmailTableViewCell.swift
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

class VCardEditEmailTableViewCell: VCardEntryTypeAwareTableViewCell, UITextFieldDelegate{

    @IBOutlet var emailView: UITextField!
    
    var email: VCard.Email! {
        didSet {
            typeView.text = self.vcardEntryTypeName(for: email.types.first);
            emailView.text = email.address;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        let typePicker = UIPickerView();
        typePicker.dataSource = self;
        typePicker.delegate = self;
        typeView.inputView = typePicker;
        
        emailView.delegate = self;
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    override func typeSelected(_ type: VCard.EntryType) {
        email.types = [type];
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        email.address = textField.text;
    }
    
}
