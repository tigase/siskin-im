//
// MucJoinViewController.swift
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

class MucJoinViewController: CustomTableViewController, UIPickerViewDataSource, UIPickerViewDelegate {

    var xmppService:XmppService!;
    
    @IBOutlet var accountTextField: UITextField!
    @IBOutlet var serverTextField: UITextField!
    @IBOutlet var roomTextField: UITextField!
    @IBOutlet var nicknameTextField: UITextField!
    @IBOutlet var passwordTextField: UITextField!
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let accountPicker = UIPickerView();
        accountPicker.dataSource = self;
        accountPicker.delegate = self;
        self.accountTextField.inputView = accountPicker;
        let accounts = AccountManager.getAccounts();
        // by default select first account        
        if !accounts.isEmpty && (self.accountTextField.text?.isEmpty ?? true) {
            self.accountTextField.text = accounts[0];
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if self.serverTextField.text?.isEmpty ?? true {
            if let jid = BareJID(accountTextField.text) {
                self.findMucComponentJid(for: jid);
            }
        }
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
        guard [accountTextField,serverTextField,roomTextField,nicknameTextField].filter(self.checkFieldValue(_:)).isEmpty else {
            return;
        }
        let accountJid = BareJID(accountTextField.text!);
        let server = serverTextField.text!;
        let room = roomTextField.text!;
        let nickname = nicknameTextField.text!;
        let password: String? = (passwordTextField.text?.isEmpty ?? true) ? nil : passwordTextField.text;
        
        let client = xmppService.getClient(forJid: accountJid);
        if let mucModule: MucModule = client?.modulesManager.getModule(MucModule.ID) {
            _ = mucModule.join(roomName: room, mucServer: server, nickname: nickname, password: password, ifCreated: { room in
                mucModule.getRoomConfiguration(roomJid: room.jid, onSuccess: { (config) in
                    mucModule.setRoomConfiguration(roomJid: room.jid, configuration: config, onSuccess: {
                        print("unlocked room", room.jid);
                    }, onError: nil);
                }, onError: nil);
            });
            PEPBookmarksModule.updateOrAdd(xmppService: xmppService, for: accountJid, bookmark: Bookmarks.Conference(name: room, jid: JID(BareJID(localPart: room, domain: server)), autojoin: true, nick: nickname, password: password));
            dismissView();
        } else {
            var alert: UIAlertController? = nil;
            if client == nil {
                alert = UIAlertController.init(title: "Warning", message: "Account is disabled.\nDo you want to enable account?", preferredStyle: .alert);
                alert?.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                alert?.addAction(UIAlertAction(title: "Yes", style: .default, handler: {(alertAction) in
                    if let account = AccountManager.getAccount(forJid: accountJid.stringValue) {
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
    
    fileprivate func findMucComponentJid(for account: BareJID) {
        self.serverTextField.text = nil;
        guard let discoModule: DiscoveryModule = xmppService.getClient(forJid: account)?.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        discoModule.getItems(for: JID(account.domain)!, onItemsReceived: { (_, items) -> Void in
            var found: Bool = false;
            let callback = { (jid: JID?) in
                DispatchQueue.main.async {
                    guard jid != nil && found == false else {
                        return;
                    }
                    found = true;
                    self.serverTextField.text = jid?.stringValue;
                }
            };
            let onError: ((ErrorCondition?)->Void)? = { error in
                callback(nil);
            };
            
            items.forEach({ (item) in
                discoModule.getInfo(for: item.jid, onInfoReceived: { (node, identities, features) in
                    guard features.contains("http://jabber.org/protocol/muc") else {
                        callback(nil);
                        return;
                    }
                    callback(item.jid);
                }, onError: onError);
            });
        }, onError: { errorCondition in
        });
    }
    
    func checkFieldValue(_ field: UITextField) -> Bool {
        guard field.text?.isEmpty ?? true else {
            return false;
        }
        
        let backgroundColor = field.superview?.backgroundColor;
        UIView.animate(withDuration: 0.5, animations: {
            //cell.backgroundColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1);
            field.superview?.backgroundColor = UIColor(hue: 0, saturation: 0.7, brightness: 0.8, alpha: 1)
        }, completion: {(b) in
            UIView.animate(withDuration: 0.5) {
                field.superview?.backgroundColor = backgroundColor;
            }
        });
        
        return true;
    }
    
    @IBAction func cancelBtnClicked(_ sender: UIBarButtonItem) {
        dismissView();
    }
    
    func dismissView() {
//        let newController = navigationController?.popViewController(animated: true);
//        if newController == nil || newController != self {
//            let emptyDetailController = storyboard!.instantiateViewController(withIdentifier: "emptyDetailViewController");
//            self.showDetailViewController(emptyDetailController, sender: self);
//        }
        self.dismiss(animated: true, completion: nil);
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
        if let jid = BareJID(self.accountTextField.text) {
            self.findMucComponentJid(for: jid);
        }
    }
}
