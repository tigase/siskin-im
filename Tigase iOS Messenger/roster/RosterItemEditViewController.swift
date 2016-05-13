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
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
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
        self.accountTextField.addTarget(self, action: #selector(RosterItemEditViewController.textFieldDidChange), forControlEvents: UIControlEvents.EditingChanged);
        self.jidTextField.addTarget(self, action: #selector(RosterItemEditViewController.textFieldDidChange), forControlEvents: UIControlEvents.EditingChanged);
        self.jidTextField.text = jid?.stringValue;
        self.accountTextField.text = account?.stringValue;
        if account != nil && jid != nil {
            self.jidTextField.enabled = false;
            self.accountTextField.enabled = false;
            
            if let sessionObject = xmppService.getClient(account!)?.sessionObject {
                if let rosterItem = xmppService.dbRosterStore.get(sessionObject, jid: jid!) {
                    self.nameTextField.text = rosterItem.name;
                }
            }
        }
        requestAuthorizationSwith.on = false;
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func textFieldDidChange(textField: UITextField) {
        if textField.text?.isEmpty != false {
            textField.layer.borderColor = UIColor.redColor().CGColor;
            textField.layer.borderWidth = 1;
            textField.layer.cornerRadius = 4;
        } else {
            textField.layer.borderColor = UIColor(white: 1, alpha: 1).CGColor;
            textField.layer.borderWidth = 0;
            textField.layer.cornerRadius = 0;
        }
    }

    @IBAction func saveBtnClicked(sender: UIBarButtonItem) {
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
            let alert = UIAlertController.init(title: "Warning", message: "Before changing roster you need to connect to server. Do you wish to do this now?", preferredStyle: .Alert);
            alert.addAction(UIAlertAction(title: "No", style: .Cancel, handler: {(alertAction) in
                self.navigationController?.popViewControllerAnimated(true);
            }));
            alert.addAction(UIAlertAction(title: "Yes", style: .Default, handler: {(alertAction) in
                if let account = AccountManager.getAccount(self.account!.stringValue) {
                    account.active = true;
                    AccountManager.updateAccount(account);
                }
            }));
            self.presentViewController(alert, animated: true, completion: nil);
            return;
        }
        
        let requestAuth = self.requestAuthorizationSwith.on;
        let onSuccess = {(stanza:Stanza)->Void in
            if requestAuth {
                if let presenceModule: PresenceModule = client?.modulesManager.getModule(PresenceModule.ID) {
                    presenceModule.subscribe(self.jid!);
                }
            }
            self.navigationController?.popViewControllerAnimated(true);
        };
        let onError = {(errorCondition:ErrorCondition?)->Void in
            let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .Alert);
            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil));
            self.presentViewController(alert, animated: true, completion: nil);
        };

        let rosterModule:RosterModule = client!.modulesManager.getModule(RosterModule.ID)!;
        if let rosterItem = rosterModule.rosterStore.get(jid!) {
            rosterItem.name = nameTextField.text;
            rosterModule.rosterStore.update(rosterItem, onSuccess: onSuccess, onError: onError);
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

    func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
        return 1;
    }
    
    func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return AccountManager.getAccounts().count;
    }
    
    func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return AccountManager.getAccounts()[row];
    }
    
    func  pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.accountTextField.text = self.pickerView(pickerView, titleForRow: row, forComponent: component);
    }
    
}
