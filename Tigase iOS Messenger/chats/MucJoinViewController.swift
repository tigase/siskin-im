//
// MucJoinViewController.swift
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

class MucJoinViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {

    var xmppService:XmppService! {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    @IBOutlet var accountTextField: UITextField!
    @IBOutlet var serverTextField: UITextField!
    @IBOutlet var roomTextField: UITextField!
    @IBOutlet var nicknameTextField: UITextField!
    @IBOutlet var passwordTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let accountPicker = UIPickerView();
        accountPicker.dataSource = self;
        accountPicker.delegate = self;
        self.accountTextField.inputView = accountPicker;
        let accounts = AccountManager.getAccounts();
        // by default select first account
        if !accounts.isEmpty {
            self.accountTextField.text = accounts[0];
        }
        self.accountTextField.addTarget(self, action: #selector(MucJoinViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
        self.serverTextField.addTarget(self, action: #selector(MucJoinViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
        self.roomTextField.addTarget(self, action: #selector(MucJoinViewController.textFieldDidChange), for: UIControlEvents.editingChanged);
        self.nicknameTextField.addTarget(self, action: #selector(MucJoinViewController.textFieldDidChange), for: UIControlEvents.editingChanged);

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    @IBAction func joinBtnClicked(_ sender: UIBarButtonItem) {
        guard accountTextField.text?.isEmpty == false && serverTextField.text?.isEmpty == false && roomTextField.text?.isEmpty == false &&  nicknameTextField.text?.isEmpty == false else {
            return;
        }
        let accountJid = BareJID(accountTextField.text!);
        let server = serverTextField.text!;
        let room = roomTextField.text!;
        let nickname = nicknameTextField.text!;
        let password = passwordTextField.text!;
        
        let client = xmppService.getClient(accountJid);
        if let mucModule: MucModule = client?.modulesManager.getModule(MucModule.ID) {
            _ = mucModule.join(room, mucServer: server, nickname: nickname, password: password);
            _ = self.navigationController?.popViewController(animated: true);
        } else {
            var alert: UIAlertController? = nil;
            if client == nil {
                alert = UIAlertController.init(title: "Warning", message: "Account is disabled.\nDo you want to enable account?", preferredStyle: .alert);
                alert?.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                alert?.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                    if let account = AccountManager.getAccount(accountJid.stringValue) {
                        account.active = true;
                        AccountManager.updateAccount(account);
                    }
                }));
            } else if client?.state != .connected {
                alert = UIAlertController.init(title: "Warning", message: "Account is disconnected.\nPlease wait until account will reconnect", preferredStyle: .alert);
                alert?.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            }
            if alert != nil {
                self.present(alert!, animated: true, completion: nil);
            }
        }
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
