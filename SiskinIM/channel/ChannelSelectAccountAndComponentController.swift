//
// ChannelSelectAccountAndComponentController.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

class ChannelSelectAccountAndComponentController: UITableViewController, UIPickerViewDataSource, UIPickerViewDelegate {

    @IBOutlet var accountField: UITextField!;
    @IBOutlet var componentField: UITextField!;
    
    weak var delegate: ChannelSelectAccountAndComponentControllerDelgate?;

    private let accountPicker = UIPickerView();
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        let accountPicker = UIPickerView();
        accountPicker.dataSource = self;
        accountPicker.delegate = self;
        accountField.inputView = accountPicker;
        accountField.text = delegate?.client?.userBareJid.stringValue;
        componentField?.text = delegate?.domain;
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if let account = BareJID(accountField!.text), let client = XmppService.instance.getClient(for: account) {
            delegate?.client = client;
        }
        let val = componentField.text?.trimmingCharacters(in: .whitespacesAndNewlines);
        delegate?.domain = (val?.isEmpty ?? true) ? nil : val;
        super.viewWillDisappear(animated);
    }
        
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1;
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return AccountManager.getActiveAccounts().count;
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return AccountManager.getActiveAccounts()[row].name.stringValue;
    }
    
    func  pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.accountField.text = self.pickerView(pickerView, titleForRow: row, forComponent: component);
    }

}

protocol ChannelSelectAccountAndComponentControllerDelgate: AnyObject {
    var client: XMPPClient? { get set }
    var domain: String? { get set }
}
