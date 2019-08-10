//
// RosterItemEditViewController.swift
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
import TigaseSwift

class RosterItemEditViewController: CustomTableViewController, UIPickerViewDataSource, UIPickerViewDelegate {

    var xmppService:XmppService!
    
    @IBOutlet var accountTextField: UITextField!
    @IBOutlet var jidTextField: UITextField!
    @IBOutlet var nameTextField: UITextField!
    @IBOutlet var sendPresenceUpdatesSwitch: UISwitch!
    @IBOutlet var receivePresenceUpdatesSwitch: UISwitch!
    
    var account:BareJID?;
    var jid:JID?;
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        super.viewDidLoad()

        // Do any additional setup after loading the view
        let accountPicker = UIPickerView();
        accountPicker.dataSource = self;
        accountPicker.delegate = self;
        self.accountTextField.inputView = accountPicker;
//        self.accountTextField.addTarget(self, action: #selector(RosterItemEditViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
//        self.jidTextField.addTarget(self, action: #selector(RosterItemEditViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
        self.jidTextField.text = jid?.stringValue;
        self.accountTextField.text = account?.stringValue;
        self.sendPresenceUpdatesSwitch.isOn = true;
        self.receivePresenceUpdatesSwitch.isOn = Settings.AutoSubscribeOnAcceptedSubscriptionRequest.getBool();
        if account != nil && jid != nil {
            self.jidTextField.isEnabled = false;
            self.accountTextField.isEnabled = false;
            
            if let sessionObject = xmppService.getClient(forJid: account!)?.sessionObject {
                let rosterStore: RosterStore = RosterModule.getRosterStore(sessionObject)
                if let rosterItem = rosterStore.get(for: jid!) {
                    self.nameTextField.text = rosterItem.name;
                    self.sendPresenceUpdatesSwitch.isOn = rosterItem.subscription.isFrom;
                    self.receivePresenceUpdatesSwitch.isOn = rosterItem.subscription.isTo;
                }
            }
        } else {
            self.nameTextField.text = nil;
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
//    func textFieldDidChange(_ textField: UITextField) {
//        if textField.text?.isEmpty != false {
//            textField.superview?.backgroundColor = UIColor.red;
////            textField.layer.borderColor = UIColor.red.cgColor;
////            textField.layer.borderWidth = 1;
//        } else {
////            textField.layer.borderColor = UIColor(white: 1, alpha: 1).cgColor;
////            textField.layer.borderWidth = 0;
//            textField.superview?.backgroundColor = UIColor.white;
//        }
//    }

    @IBAction func saveBtnClicked(_ sender: UIBarButtonItem) {
        saveChanges()
    }
    
    @IBAction func cancelBtnClicked(_ sender: UIBarButtonItem) {
        dismissView();
    }
    
    func dismissView() {
        self.dismiss(animated: true, completion: nil);
    }
    
    func blinkError(_ field: UITextField) {
        let backgroundColor = field.superview?.backgroundColor;
        UIView.animate(withDuration: 0.5, animations: {
            //cell.backgroundColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1);
            field.superview?.backgroundColor = UIColor(hue: 0, saturation: 0.7, brightness: 0.8, alpha: 1)
        }, completion: {(b) in
            UIView.animate(withDuration: 0.5) {
                field.superview?.backgroundColor = backgroundColor;
            }
        });
    }
    
    func saveChanges() {
        var fieldsWithErrors: [UITextField] = [];
        if JID((jidTextField.text?.isEmpty ?? true) ? nil : jidTextField.text) == nil {
            fieldsWithErrors.append(jidTextField);
        }
        if BareJID((accountTextField.text?.isEmpty ?? true) ? nil : accountTextField.text) == nil {
            fieldsWithErrors.append(accountTextField);
        }
        guard fieldsWithErrors.isEmpty else {
            fieldsWithErrors.forEach(self.blinkError(_:));
            return;
        }
        jid = JID(jidTextField.text!);
        account = BareJID(accountTextField.text!);
        let client = xmppService.getClient(forJid: account!);
        guard client?.state == SocketConnector.State.connected else {
            let alert = UIAlertController.init(title: "Warning", message: "Before changing roster you need to connect to server. Do you wish to do this now?", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: {(alertAction) in
                _ = self.navigationController?.popViewController(animated: true);
            }));
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                if let account = AccountManager.getAccount(forJid: self.account!.stringValue) {
                    account.active = true;
                    AccountManager.updateAccount(account);
                }
            }));
            self.present(alert, animated: true, completion: nil);
            return;
        }
        
        let onSuccess = {(stanza:Stanza)->Void in
            self.updateSubscriptions(client: client!);
            DispatchQueue.main.async {
                self.dismissView();
            }
        };
        let onError = {(errorCondition:ErrorCondition?)->Void in
            DispatchQueue.main.async {
                let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                self.present(alert, animated: true, completion: nil);
            }
        };

        let rosterModule:RosterModule = client!.modulesManager.getModule(RosterModule.ID)!;
        if let rosterItem = rosterModule.rosterStore.get(for: jid!) {
            if rosterItem.name == nameTextField.text {
                updateSubscriptions(client: client!);
                self.dismissView();
            } else {
                rosterModule.rosterStore.update(item: rosterItem, name: nameTextField.text, onSuccess: onSuccess, onError: onError);
            }
        } else {
            rosterModule.rosterStore.add(jid: jid!, name: nameTextField.text, onSuccess: onSuccess, onError: onError);
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return nil;
    }
    
    fileprivate func updateSubscriptions(client: XMPPClient) {
        let rosterModule:RosterModule = client.modulesManager.getModule(RosterModule.ID)!;
        if let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) {
            guard let rosterItem = rosterModule.rosterStore.get(for: self.jid!) else {
                return;
            }
            DispatchQueue.main.async {
                if self.receivePresenceUpdatesSwitch.isOn && !rosterItem.subscription.isTo {
                    presenceModule.subscribe(to: self.jid!);
                }
                if !self.receivePresenceUpdatesSwitch.isOn && rosterItem.subscription.isTo {
                    presenceModule.unsubscribe(from: self.jid!);
                }
                if self.sendPresenceUpdatesSwitch.isOn && !rosterItem.subscription.isFrom {
                    presenceModule.subscribed(by: self.jid!);
                }
                if !self.sendPresenceUpdatesSwitch.isOn && rosterItem.subscription.isFrom {
                    presenceModule.unsubscribed(by: self.jid!);
                }
            }
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
