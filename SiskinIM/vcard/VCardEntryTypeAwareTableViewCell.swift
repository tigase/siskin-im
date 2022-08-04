//
// VCardEntryTypeAwareTableViewCell.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class VCardEntryTypeAwareTableViewCell: UITableViewCell, UIPickerViewDelegate, UIPickerViewDataSource {
    
    @IBOutlet var typeView: UITextField!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        let typePicker = UIPickerView();
        typePicker.dataSource = self;
        typePicker.delegate = self;
        typeView.inputView = typePicker;
        if #available(iOS 13.0, *) {
            let btn = UIButton(type: .detailDisclosure);
            btn.isEnabled = false;
            btn.setImage(UIImage(systemName: "chevron.right"), for: .normal);
            typeView.rightView = btn;
            typeView.rightViewMode = .always;
        }
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
    
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        guard let title = self.pickerView(pickerView, titleForRow: row, forComponent: component) else {
            return nil;
        }
        if #available(iOS 13.0, *) {
            return NSAttributedString(string: title, attributes: [.foregroundColor : UIColor.label]);
        } else {
            return NSAttributedString(string: title, attributes: [.foregroundColor : UIColor.darkText]);
        }
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
            return NSLocalizedString("Home", comment: "address type label");
        case .work:
            return NSLocalizedString("Work", comment: "address type label");
        }
    }
}

