//
// VCardEditAddressTableViewCell.swift
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

class VCardEditAddressTableViewCell: VCardEntryTypeAwareTableViewCell, UITextFieldDelegate {

    var address: VCard.Address! {
        didSet {
            typeView.text = vcardEntryTypeName(for: address.types.first);
            streetView.text = address.street;
            postalCodeView.text = address.postalCode;
            cityView.text = address.locality;
            countryView.text = address.country;
        }
    }
    
    @IBOutlet var streetView: UITextField!
    @IBOutlet var postalCodeView: UITextField!
    @IBOutlet var cityView: UITextField!
    @IBOutlet var countryView: UITextField!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        streetView.delegate = self;
        postalCodeView.delegate = self;
        countryView.delegate = self;
        cityView.delegate = self;
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    override func typeSelected(_ type: VCard.EntryType) {
        address.types = [type];
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        switch textField {
        case streetView:
            address.street = textField.text;
        case postalCodeView:
            address.postalCode = textField.text;
        case cityView:
            address.locality = textField.text;
        case countryView:
            address.country = textField.text;
        default:
            break;
        }
    }
    
}
