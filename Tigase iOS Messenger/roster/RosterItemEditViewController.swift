//
// RosterItemEditViewController.swift
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

class RosterItemEditViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {

    var xmppService:XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    @IBOutlet var accountTextField: UITextField!
    @IBOutlet var jidTextField: UITextField!
    @IBOutlet var nameTextField: UITextField!
    @IBOutlet var requestAuthorizationSwith: UISwitch!
    
    var account:BareJID?;
    var jid:JID?;
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view
        let accountPicker = UIPickerView();
        accountPicker.dataSource = self;
        accountPicker.delegate = self;
        self.accountTextField.inputView = accountPicker;
        self.accountTextField.addTarget(self, action: #selector(RosterItemEditViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
        self.jidTextField.addTarget(self, action: #selector(RosterItemEditViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
        self.jidTextField.text = jid?.stringValue;
        self.accountTextField.text = account?.stringValue;
        if account != nil && jid != nil {
            self.jidTextField.isEnabled = false;
            self.accountTextField.isEnabled = false;
            
            if let sessionObject = xmppService.getClient(account!)?.sessionObject {
                let rosterStore: RosterStore = RosterModule.getRosterStore(sessionObject)
                if let rosterItem = rosterStore.get(jid!) {
                    self.nameTextField.text = rosterItem.name;
                }
            }
        }
        requestAuthorizationSwith.isOn = false;
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func textFieldDidChange(_ textField: UITextField) {
        if textField.text?.isEmpty != false {
            textField.layer.borderColor = UIColor.red.cgColor;
            textField.layer.borderWidth = 1;
            textField.layer.cornerRadius = 4;
        } else {
            textField.layer.borderColor = UIColor(white: 1, alpha: 1).cgColor;
            textField.layer.borderWidth = 0;
            textField.layer.cornerRadius = 0;
        }
    }

    @IBAction func saveBtnClicked(_ sender: UIBarButtonItem) {
        saveChanges()
    }
    
    func saveChanges() {
        guard jidTextField.text?.isEmpty != true else {
            textFieldDidChange(jidTextField);
            return;
        }
        guard accountTextField.text?.isEmpty != true else {
            textFieldDidChange(accountTextField);
            return;
        }
        jid = JID(jidTextField.text!);
        account = BareJID(accountTextField.text!);
        let client = xmppService.getClient(account!);
        guard client?.state == SocketConnector.State.connected else {
            let alert = UIAlertController.init(title: "Warning", message: "Before changing roster you need to connect to server. Do you wish to do this now?", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: {(alertAction) in
                _ = self.navigationController?.popViewController(animated: true);
            }));
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                if let account = AccountManager.getAccount(self.account!.stringValue) {
                    account.active = true;
                    AccountManager.updateAccount(account);
                }
            }));
            self.present(alert, animated: true, completion: nil);
            return;
        }
        
        let requestAuth = self.requestAuthorizationSwith.isOn;
        let onSuccess = {(stanza:Stanza)->Void in
            if requestAuth {
                if let presenceModule: PresenceModule = client?.modulesManager.getModule(PresenceModule.ID) {
                    presenceModule.subscribe(self.jid!);
                }
            }
            _ = self.navigationController?.popViewController(animated: true);
        };
        let onError = {(errorCondition:ErrorCondition?)->Void in
            let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.present(alert, animated: true, completion: nil);
        };

        let rosterModule:RosterModule = client!.modulesManager.getModule(RosterModule.ID)!;
        if let rosterItem = rosterModule.rosterStore.get(jid!) {
            rosterModule.rosterStore.update(rosterItem, name: nameTextField.text, onSuccess: onSuccess, onError: onError);
        } else {
            rosterModule.rosterStore.add(jid!, name: nameTextField.text, onSuccess: onSuccess, onError: onError);
        }
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1;
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return AccountManager.getAccounts().count;
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return AccountManager.getAccounts()[row];
    }
    
    func  pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.accountTextField.text = self.pickerView(pickerView, titleForRow: row, forComponent: component);
    }
    
}
