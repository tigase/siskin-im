//
// VCardEditPhoneTableViewCell.swift
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

class VCardEditPhoneTableViewCell: UITableViewCell, UIPickerViewDelegate, UIPickerViewDataSource, UITextFieldDelegate {
    
    @IBOutlet var typeView: UITextField!
    
    @IBOutlet var phoneView: UITextField!
    
    var phone: VCardModule.VCard.Telephone! {
        didSet {
            phoneView.text = phone.number;
            typeView.text = phone.types.first?.rawValue.capitalized;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
        let typePicker = UIPickerView();
        typePicker.dataSource = self;
        typePicker.delegate = self;
        typeView.inputView = typePicker;
        
        phoneView.delegate = self;
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let type = VCardModule.VCard.EntryType.allValues[row];
        phone.types = [type];
        typeView.text = type.rawValue.capitalized;
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let type = VCardModule.VCard.EntryType.allValues[row];
        return type.rawValue.capitalized;
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1;
    }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return VCardModule.VCard.EntryType.allValues.count;
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        phone.number = textField.text;
    }
}
