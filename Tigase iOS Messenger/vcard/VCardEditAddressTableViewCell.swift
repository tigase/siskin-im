//
// VCardEditAddressTableViewCell.swift
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

class VCardEditAddressTableViewCell: UITableViewCell, UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource {

    var address: VCardModule.VCard.Address! {
        didSet {
            typeView.text = address.types.first?.rawValue.capitalizedString;
            streetView.text = address.street;
            postalCodeView.text = address.postalCode;
            cityView.text = address.locality;
            countryView.text = address.country;
        }
    }
    
    @IBOutlet var typeView: UITextField!
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
        let typePicker = UIPickerView();
        typePicker.dataSource = self;
        typePicker.delegate = self;
        typeView.inputView = typePicker;
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let type = VCardModule.VCard.Type.allValues[row];
        address.types = [type];
        typeView.text = type.rawValue.capitalizedString;
    }
    
    func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let type = VCardModule.VCard.Type.allValues[row];
        return type.rawValue.capitalizedString;
    }
    
    func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
        return 1;
    }
    func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return VCardModule.VCard.Type.allValues.count;
    }

    func textFieldDidEndEditing(textField: UITextField) {
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
