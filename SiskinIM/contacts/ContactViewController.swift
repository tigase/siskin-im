//
// ContactViewController.swift
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
import TigaseSwiftOMEMO

class ContactViewController: UITableViewController {
    
    var account: BareJID!;
    var jid: BareJID!;
    var vcard: VCard? {
        didSet {
            self.reloadData();
        }
    }
    
    var encryption: ChatEncryption? {
        get {
            return chat?.options.encryption;
        }
    }
    var chat: Chat?;
    var omemoIdentities: [Identity] = [];
    
    var addresses: [VCard.Address] {
        return vcard?.addresses ?? [];
    }
    var phones: [VCard.Telephone] {
        return vcard?.telephones ?? [];
    }
    var emails: [VCard.Email] {
        return vcard?.emails ?? [];
    }
    
    
    fileprivate var sections: [Sections] = [.basic];
    
    override func viewDidLoad() {
        super.viewDidLoad()

//        if self.chat == nil {
//            chat = DBChatStore.instance.getChat(for: account, with: jid) as? DBChat;
//        }
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        vcard = XmppService.instance.dbVCardsCache.getVCard(for: jid);
        if vcard == nil {
            refreshVCard();
        }
        omemoIdentities = DBOMEMOStore.instance.identities(forAccount: account, andName: jid.stringValue);
        tableView.contentInset = UIEdgeInsets(top: -1, left: 0, bottom: 0, right: 0);
        tableView.reloadData();
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func doneClicked(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func refreshVCard(_ sender: UIBarButtonItem) {
        refreshVCard();
    }
    
    func refreshVCard() {
        DispatchQueue.global(qos: .background).async() {
            XmppService.instance.refreshVCard(account: self.account, for: self.jid, onSuccess: { (vcard) in
                DispatchQueue.main.async {
                    self.vcard = vcard;
                }
            }, onError: { (errorCondition) in
                
            });
        }
    }
    
    func reloadData() {
        var sections: [Sections] = [.basic];
        if chat != nil {
            sections.append(.settings);
            sections.append(.attachments);
            sections.append(.encryption);
        }
        if phones.count > 0 {
            sections.append(.phones);
        }
        if emails.count > 0 {
            sections.append(.emails);
        }
        if addresses.count > 0 {
            sections.append(.addresses);
        }
        self.sections = sections;
        tableView.reloadData();
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in: UITableView) -> Int {
        return sections.count;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection sectionNo: Int) -> Int {
        switch sections[sectionNo] {
        case .basic:
            return 1;
        case .settings:
            return 2;
        case .attachments:
            return 1;
        case .encryption:
            return omemoIdentities.count + 1;
        case .phones:
            return phones.count;
        case .emails:
            return emails.count;
        case .addresses:
            return addresses.count;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection sectionNo: Int) -> String? {
        return sections[sectionNo].label;
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return 1.0;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "";
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .basic:
            let cell = tableView.dequeueReusableCell(withIdentifier: "BasicInfoCell", for: indexPath) as! ContactBasicTableViewCell;
        
            cell.account = account;
            cell.jid = jid;
            cell.vcard = vcard;
        
            return cell;
        case .settings:
            switch SettingsOptions(rawValue: indexPath.row)! {
            case .mute:
                let cell = tableView.dequeueReusableCell(withIdentifier: "MuteContactCell", for: indexPath);
                let btn = UISwitch(frame: .zero);
                btn.isOn = (chat?.options.notifications ?? .always == .none);
                btn.isEnabled = chat != nil;
                btn.addTarget(self, action: #selector(muteContactChanged), for: .valueChanged);
                cell.accessoryView = btn;
                return cell;
            case .block:
                let cell = tableView.dequeueReusableCell(withIdentifier: "BlockContactCell", for: indexPath);
                let btn = UISwitch(frame: .zero);
                if let client = XmppService.instance.getClient(for: account), let blockingModule: BlockingCommandModule = client.modulesManager.getModule(BlockingCommandModule.ID), blockingModule.isAvailable {
                    btn.isOn = BlockedEventHandler.isBlocked(JID(jid), on: client);
                    btn.isEnabled = client.state == .connected;
                } else {
                    btn.isOn = false;
                    btn.isEnabled = false;
                }
                btn.addTarget(self, action: #selector(blockContactChanged), for: .valueChanged);
                cell.accessoryView = btn;
                return cell;
            }
        case .attachments:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AttachmentsCell", for: indexPath);
            return cell;
        case .encryption:
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "OMEMOEncryptionCell", for: indexPath);
                if self.encryption != nil {
                    switch self.encryption! {
                    case .none:
                        cell.detailTextLabel?.text = "None";
                    case .omemo:
                        cell.detailTextLabel?.text = "OMEMO";
                    }
                } else {
                    cell.detailTextLabel?.text = "Default";
                }
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "OMEMOIdentityCell", for: indexPath) as! OMEMOIdentityTableViewCell;
                let identity = omemoIdentities[indexPath.row - 1];
                var fingerprint = String(identity.fingerprint.dropFirst(2));
                var idx = fingerprint.startIndex;
                for _ in 0..<(fingerprint.count / 8) {
                    idx = fingerprint.index(idx, offsetBy: 8);
                    fingerprint.insert(" ", at: idx);
                    idx = fingerprint.index(after: idx);
                }
                cell.identityLabel.text = fingerprint;
                cell.trustSwitch.isEnabled = identity.status.isActive;
                cell.trustSwitch.isOn = identity.status.trust == .trusted || identity.status.trust == .undecided;
                let account = self.account!;
                cell.valueChangedListener = { (sender) in
                    _ = DBOMEMOStore.instance.setStatus(identity.status.toTrust(sender.isOn ? .trusted : .compromised), forIdentity: identity.address, andAccount: account);
                }
                return cell;
            }
        case .phones:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath) as! ContactFormTableViewCell;
            let phone = phones[indexPath.row];
            let type = getVCardEntryTypeLabel(for: phone.types.first ?? VCard.EntryType.home);
            
            cell.typeView.text = type;
            cell.labelView.text = phone.number?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            
            return cell;
        case .emails:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath) as! ContactFormTableViewCell;
            let email = emails[indexPath.row];
            let type = getVCardEntryTypeLabel(for: email.types.first ?? VCard.EntryType.home);
            
            cell.typeView.text = type;
            cell.labelView.text = email.address?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            
            return cell;
        case .addresses:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddressCell", for: indexPath ) as! ContactFormTableViewCell;
            let address = addresses[indexPath.row];
            let type = getVCardEntryTypeLabel(for: address.types.first ?? VCard.EntryType.home);
            
            cell.typeView.text = type;
            
            var text = "";
            var start = true;
            if let street = address.street {
                text += street;
                start = false;
            }
            if let code = address.postalCode {
                if !start {
                    text += "\n";
                }
                text += code + " ";
                start = false;
            }
            if let locality = address.locality {
                if !start && address.postalCode == nil {
                    text += "\n";
                }
                text += locality;
                start = false;
            }
            if let country = address.country {
                if !start {
                    text += "\n";
                }
                text += country;
                start = false;
            }
            
            cell.labelView.text = text;
            
            return cell;
//        default:
//            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath as IndexPath) as! ContactFormTableViewCell;
//            return cell;
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 0 {
            return nil;
        }
        return indexPath;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true)
        switch sections[indexPath.section] {
        case .basic:
            return;
        case .settings:
            return;
        case .attachments:
            return;
        case .encryption:
            if indexPath.row == 0 {
                // handle change of encryption method!
                let current = self.encryption;
                let controller = TablePickerViewController(style: .grouped);
                let values: [ChatEncryption?] = [nil, ChatEncryption.none, ChatEncryption.omemo];
                controller.selected = current == nil ? 0 : (current! == .omemo ? 2 : 1);
                controller.items = values.map({ (it)->TablePickerViewItemsProtocol in
                    return ContactMessageEncryptionItem(value: it);
                });
                //controller.selected = 1;
                controller.onSelectionChange = { (_item) -> Void in
                    guard let item = _item as? ContactMessageEncryptionItem, let chat = self.chat else {
                        return;
                    }
                    
                    chat.modifyOptions({ (options) in
                        options.encryption = item.value;
                    }) {
                        DispatchQueue.main.async {
                            self.reloadData();
                        }
                    }
                };
                self.navigationController?.pushViewController(controller, animated: true);

            }
        case .phones:
            if let url = URL(string: "tel:" + phones[indexPath.row].number!) {
                UIApplication.shared.open(url);
            }
        case .emails:
            if let url = URL(string: "mailto:" + emails[indexPath.row].address!) {
                UIApplication.shared.open(url);
            }
        case .addresses:
            let address = addresses[indexPath.row];
            var parts = [String]();
            if let street = address.street {
                parts.append(street);
            }
            if let locality = address.locality {
                parts.append(locality);
            }
            if let country = address.country {
                parts.append(country);
            }
            let query = parts.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!;
            if let url = URL(string: "http://maps.apple.com/?q=" + query) {
                UIApplication.shared.open(url);
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "chatShowAttachments" {
            if let attachmentsController = segue.destination as? ChatAttachmentsController {
                attachmentsController.account = self.account;
                attachmentsController.jid = self.jid;
            }
        }
    }
    
    func getVCardEntryTypeLabel(for type: VCard.EntryType) -> String? {
        switch type {
        case .home:
            return "Home";
        case .work:
            return "Work";
        }
    }
    
    @objc func blockContactChanged(_ sender: UISwitch) {
        guard let client = XmppService.instance.getClient(for: account), let blockingModule: BlockingCommandModule = client.modulesManager.getModule(BlockingCommandModule.ID) else {
            sender.isOn = !sender.isOn;
            return;
        }

        if sender.isOn {
            blockingModule.block(jids: [JID(jid!)], completionHandler: { [weak sender] result in
                switch result {
                case .failure(_):
                    sender?.isOn = false;
                default:
                    break;
                }
            })
        } else {
            blockingModule.unblock(jids: [JID(jid!)], completionHandler: { [weak sender] result in
                switch result {
                case .failure(_):
                    sender?.isOn = true;
                default:
                    break;
                }
            })
        }
    }
    
    @objc func muteContactChanged(_ sender: UISwitch) {
        guard let account = self.account else {
            sender.isOn = !sender.isOn;
            return;
        }
        chat?.modifyOptions({ (options) in
            options.notifications = sender.isOn ? .none : .always;
        }, completionHandler: {
            if let client = XmppService.instance.getClient(for: account), let pushModule: SiskinPushNotificationsModule = client.modulesManager.getModule(SiskinPushNotificationsModule.ID), let pushSettings = pushModule.pushSettings {
                pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                    switch result {
                    case .success(_):
                        break;
                    case .failure(_):
                        AccountSettings.pushHash(account).set(int: 0);
                    }
                });
            }
        });
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    internal class ContactMessageEncryptionItem: TablePickerViewItemsProtocol {
        
        public static func description(of value: ChatEncryption?) -> String {
            guard value != nil else {
                return "Default";
            }
            switch value! {
            case .omemo:
                return "OMEMO";
            case .none:
                return "None";
            }
        }
        
        let description: String;
        let value: ChatEncryption?;
        
        init(value: ChatEncryption?) {
            self.value = value;
            self.description = ContactMessageEncryptionItem.description(of: value);
        }
        
    }
    
    enum Sections {
        case basic
        case settings
        case attachments
        case encryption
        case phones
        case emails
        case addresses
        
        var label: String {
            switch self {
            case .basic:
                return "";
            case .settings:
                return "Settings";
            case .attachments:
                return "";
            case .encryption:
                return "Encryption";
            case .phones:
                return "Phones";
            case .emails:
                return "Emails";
            case .addresses:
                return "Addresses";
            }
        }
    }
    
    enum SettingsOptions: Int {
        case mute = 0
        case block = 1
    }
    
}
