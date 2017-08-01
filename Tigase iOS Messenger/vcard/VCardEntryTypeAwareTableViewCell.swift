//
// VCardEntryTypeAwareTableViewCell.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class VCardEntryTypeAwareTableViewCell: UITableViewCell, UIPickerViewDelegate, UIPickerViewDataSource {
    
    @IBOutlet var typeView: UITextField!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        let typePicker = UIPickerView();
        typePicker.dataSource = self;
        typePicker.delegate = self;
        typeView.inputView = typePicker;
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Configure the view for the selected state
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let type = VCard.EntryType.allValues[row];
        typeSelected(type);
        typeView.text = vcardEntryTypeName(for: type);
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let type = VCard.EntryType.allValues[row];
        return vcardEntryTypeName(for: type);
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1;
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return VCard.EntryType.allValues.count;
    }
    
    func typeSelected(_ type: VCard.EntryType) {
        
    }
    
    func vcardEntryTypeName(for type: VCard.EntryType?) -> String? {
        guard type != nil else {
            return nil;
        }
        switch type! {
        case .home:
            return "Home";
        case .work:
            return "Work";
        default:
            return nil;
        }
    }
}

