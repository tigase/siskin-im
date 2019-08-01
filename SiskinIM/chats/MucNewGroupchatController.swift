//
// MucNewGroupchatController.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class MucNewGroupchatController: CustomTableViewController, UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate {
    
    var xmppService: XmppService!;
    var accountPicker: UIPickerView! = UIPickerView();
    var accounts: [BareJID]!;
    
    var groupchatType: GroupchatType = .privateGroupchat;
    var mucServer: JID? = nil {
        didSet {
            self.updateXmppAddress();
            self.updateNextEnabled();
        }
    }
    
    @IBOutlet var accountField: UITextField!
    @IBOutlet var roomNameField: UITextField!
    @IBOutlet var roomNicknameField: UITextField!
    @IBOutlet var nextButton: UIBarButtonItem!
    @IBOutlet var xmppAddress: UITextField?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        self.accounts = xmppService.getClients { (client) -> Bool in
            client.state == .connected
            }.map({ (client) -> BareJID in
                return client.sessionObject.userBareJid!;
            }).sorted(by: { (j1, j2) -> Bool in
                return j1.stringValue < j2.stringValue;
            })

        accountPicker.delegate = self;
        accountPicker.dataSource = self;

        accountField.inputView = accountPicker;
        accountField.text = accounts?.first?.stringValue;
        if let account = accounts.first {
            let vcard = xmppService.dbVCardsCache.getVCard(for: account);
            roomNicknameField.text = vcard?.nicknames.first ?? vcard?.givenName ?? vcard?.fn;
        }

        accountField.delegate = self;
        roomNameField.delegate = self;
        roomNicknameField.delegate = self;
        xmppAddress?.delegate = self;
        
        accountField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged);
        roomNameField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged);
        roomNicknameField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged);
        xmppAddress?.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged);
        
        updateNextEnabled();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if self.groupchatType == .privateGroupchat {
            nextButton.title = "Choose participants";
        } else {
            nextButton.title = "Create";
        }
        super.viewWillAppear(animated);
        if let account = BareJID(self.accountField.text) {
            findMucComponentJid(for: account);
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.groupchatType == .privateGroupchat ? 3 : 4;
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1;
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return accounts.count;
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return accounts[row].stringValue;
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        accountField.text = accounts[row].stringValue;
        let vcard = xmppService.dbVCardsCache.getVCard(for: accounts[row]);
        roomNicknameField.text = vcard?.nicknames.first ?? vcard?.givenName ?? vcard?.fn;
        findMucComponentJid(for: accounts[row]);
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == self.roomNameField {
            self.updateXmppAddress();
        }
        updateNextEnabled();
    }
    
    func updateXmppAddress() {
        if let roomName = roomNameField.text, let mucServerDomain = self.mucServer?.domain {
            self.xmppAddress?.text = BareJID(localPart: roomName.lowercased().replacingOccurrences(of: " ", with: "-"), domain: mucServerDomain).stringValue;
        } else {
            self.xmppAddress?.text = nil;
        }
    }
    
    @objc func textFieldDidChange(_ sender: UITextField) {
        self.textFieldDidEndEditing(sender);
    }

    func updateNextEnabled() {
        switch groupchatType {
        case .privateGroupchat:
            self.nextButton.isEnabled = mucServer != nil && isNotEmpty(accountField) && isNotEmpty(roomNameField) && isNotEmpty(roomNicknameField);
        case .publicGroupchat:
            self.nextButton.isEnabled = mucServer != nil && isNotEmpty(accountField) && isNotEmpty(roomNameField) && isNotEmpty(roomNicknameField) && isNotEmpty(xmppAddress);
        }
    }
    
    fileprivate func isNotEmpty(_ field: UITextField?) -> Bool {
        return !(field?.text?.isEmpty ?? true);
    }
    
    fileprivate func findMucComponentJid(for account: BareJID) {
        mucServer = nil;
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
                    self.mucServer = jid;
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
    
    @IBAction func cancelClicked(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func nextClicked(_ sender: UIBarButtonItem) {
        self.accountField.resignFirstResponder();
        self.roomNameField.resignFirstResponder();
        self.roomNicknameField.resignFirstResponder();
        self.xmppAddress?.resignFirstResponder();

        switch self.groupchatType {
        case .privateGroupchat:
            let controller = self.storyboard!.instantiateViewController(withIdentifier: "InviteViewController") as! InviteViewController;
            let xmppService = self.xmppService!;
            let accountJid = BareJID(self.accountField.text!);
            let client = xmppService.getClient(forJid: accountJid)!;
            let mucServerDomain = self.mucServer!.domain!;
            let roomName = self.roomNameField.text!;
            let roomNickname = self.roomNicknameField.text!;
            controller.tableView.allowsMultipleSelection = true;
            controller.onNext = { (participants) in
                print("called onNext!");
                guard let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID) else {
                    return;
                }
                _ = mucModule.join(roomName: UUID().uuidString, mucServer: mucServerDomain, nickname: roomNickname, ifCreated: { room in
                    mucModule.getRoomConfiguration(roomJid: room.jid, onSuccess: { (config) in
                        if let roomNameField: TextSingleField = config.getField(named: "muc#roomconfig_roomname") {
                            roomNameField.value = roomName;
                        }
                        if let membersOnlyField: BooleanField = config.getField(named: "muc#roomconfig_membersonly") {
                            membersOnlyField.value = true;
                        }
                        if let persistantField: BooleanField = config.getField(named: "muc#roomconfig_persistentroom") {
                            persistantField.value = true;
                        }
                        if let publicallySeachableField: BooleanField = config.getField(named: "muc#roomconfig_publicroom") {
                            publicallySeachableField.value = false;
                        }
                        mucModule.setRoomConfiguration(roomJid: room.jid, configuration: config, onSuccess: {
                            print("unlocked room", room.jid);
                            participants.forEach({ (participant) in
                                mucModule.invite(to: room, invitee: participant, reason: "You are invied to join conversation \(roomName) at \(room.roomJid)");
                            })
                            PEPBookmarksModule.updateOrAdd(xmppService: xmppService, for: accountJid, bookmark: Bookmarks.Conference(name: roomName, jid: room.jid, autojoin: true, nick: roomNickname, password: nil));
                        }, onError: nil);
                    }, onError: nil);
                }, onJoined: { room in
                    room.registerForTigasePushNotification(true, completionHandler: { (result) in
                        print("automatically enabled push for:", room.roomJid, "result:", result);
                    })
                });
            };
            self.navigationController?.pushViewController(controller, animated: true);
            break;
        case .publicGroupchat:
            let accountJid = BareJID(self.accountField.text!);
            let client = self.xmppService!.getClient(forJid: accountJid)!;
            guard let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            guard let roomJid = BareJID(self.xmppAddress?.text), roomJid.localPart != nil else {
                return;
            }
            let roomName = self.roomNameField.text!;
            let roomNickname = self.roomNicknameField.text!;
            _ = mucModule.join(roomName: roomJid.localPart!, mucServer: roomJid.domain, nickname: roomNickname, ifCreated: { room in
                mucModule.getRoomConfiguration(roomJid: room.jid, onSuccess: { (config) in
                    if let roomNameField: TextSingleField = config.getField(named: "muc#roomconfig_roomname") {
                        roomNameField.value = roomName;
                    }
                    if let membersOnlyField: BooleanField = config.getField(named: "muc#roomconfig_membersonly") {
                        membersOnlyField.value = false;
                    }
                    if let persistantField: BooleanField = config.getField(named: "muc#roomconfig_persistentroom") {
                        persistantField.value = true;
                    }
                    if let publicallySeachableField: BooleanField = config.getField(named: "muc#roomconfig_publicroom") {
                        publicallySeachableField.value = true;
                    }
                    if let allowInvitationsField: BooleanField = config.getField(named: "muc#roomconfig_allowinvites") {
                        allowInvitationsField.value = true;
                    }
                    mucModule.setRoomConfiguration(roomJid: room.jid, configuration: config, onSuccess: {
                        print("unlocked room", room.jid);
                        PEPBookmarksModule.updateOrAdd(xmppService: self.xmppService, for: accountJid, bookmark:  Bookmarks.Conference(name: roomName, jid: room.jid, autojoin: true, nick: roomNickname, password: nil));
                    }, onError: nil);
                }, onError: nil);
            }, onJoined: { room in
                room.registerForTigasePushNotification(true, completionHandler: { (result) in
                    print("automatically enabled push for:", room.roomJid, "result:", result);
                })
            });
            
            self.dismiss(animated: true, completion: nil);
            
            break;
        }
    }
    
    enum GroupchatType {
        case privateGroupchat
        case publicGroupchat
    }
}
