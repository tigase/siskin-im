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
import Martin
import MartinOMEMO
import Shared

class ContactViewController: UITableViewController {
    
    var account: BareJID!;
    var jid: BareJID!;
    var vcard: VCard? {
        didSet {
            self.reloadData();
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

        Task {
            if let vcard = await DBVCardStore.instance.vcard(for: jid) {
                DispatchQueue.main.async {
                    self.vcard = vcard;
                }
            } else {
                try await refreshVCard();
            }
        }
        omemoIdentities = DBOMEMOStore.instance.identities(forAccount: account, andName: jid.description);
        tableView.contentInset = UIEdgeInsets(top: -1, left: 0, bottom: 0, right: 0);
        reloadData();
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func doneClicked(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func refreshVCard(_ sender: UIBarButtonItem) {
        Task {
            try await refreshVCard();
        }
    }
    
    func refreshVCard() async throws {
        let vcard = try await VCardManager.instance.refreshVCard(for: self.jid, on: self.account);
        DispatchQueue.main.async {
            self.vcard = vcard;
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
                if let blockingModule = XmppService.instance.getClient(for: account)?.module(.blockingCommand), blockingModule.isAvailable {
                    btn.isOn = blockingModule.blockedJids?.contains(JID(jid)) ?? false;
                    btn.isEnabled = true;
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
                let cell = tableView.dequeueReusableCell(withIdentifier: "OMEMOEncryptionCell", for: indexPath) as! EnumTableViewCell;
                if let chat = self.chat {
                    cell.bind({ cell in
                        cell.assign(from: chat.optionsPublisher.map({ $0.encryption?.description ?? NSLocalizedString("Default", comment: "encryption default label") }).receive(on: DispatchQueue.main).eraseToAnyPublisher());
                    })
                } else {
                    cell.detailTextLabel?.text = NSLocalizedString("Default", comment: "encryption default label");
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
                cell.deviceLabel?.text = String.localizedStringWithFormat(NSLocalizedString("Device: %@", comment: "label for omemo device id"), "\(identity.address.deviceId)");
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
            cell.iconView.image = UIImage(systemName: "phone")
            return cell;
        case .emails:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath) as! ContactFormTableViewCell;
            let email = emails[indexPath.row];
            let type = getVCardEntryTypeLabel(for: email.types.first ?? VCard.EntryType.home);
            
            cell.typeView.text = type;
            cell.labelView.text = email.address?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            cell.iconView.image = UIImage(systemName: "mail")
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
                let controller = TablePickerViewController<ChatEncryption?>(style: .grouped, options: [nil, ChatEncryption.none, ChatEncryption.omemo], value: chat?.options.encryption, labelFn: { value in
                    guard let v = value else {
                        return NSLocalizedString("Default", comment: "encryption default label");
                    }
                    return v.description;
                });
                controller.sink(receiveValue: { [weak self] value in
                    self?.chat?.updateOptions({ options in
                        options.encryption = value;
                    })
                });
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
            ContactViewController.openInMaps(address: address);
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "chatShowAttachments" {
            if let attachmentsController = segue.destination as? ChatAttachmentsController {
                attachmentsController.conversation = self.chat;
            }
        }
    }
    
    func getVCardEntryTypeLabel(for type: VCard.EntryType) -> String? {
        switch type {
        case .home:
            return NSLocalizedString("Home", comment: "address type");
        case .work:
            return NSLocalizedString("Work", comment: "address type");
        }
    }
    
    @objc func blockContactChanged(_ sender: UISwitch) {
        guard let blockingModule = XmppService.instance.getClient(for: account)?.module(.blockingCommand) else {
            sender.isOn = !sender.isOn;
            return;
        }

        let jid = JID(self.jid!);
        let account = self.account!;
        if sender.isOn {
            if DBRosterStore.instance.item(for: account, jid: jid) == nil {
                InvitationManager.instance.rejectPresenceSubscription(for: account, from: jid);
            }
            Task {
                do {
                    try await blockingModule.block(jids: [jid]);
                } catch {
                    await MainActor.run(body: {
                        sender.isOn = false;
                    })
                }
            }
        } else {
            Task {
                do {
                    try await blockingModule.unblock(jids: [jid]);
                } catch {
                    await MainActor.run(body: {
                        sender.isOn = true;
                    })
                }
            }
        }
    }
    
    @objc func muteContactChanged(_ sender: UISwitch) {
        guard let account = self.account else {
            sender.isOn = !sender.isOn;
            return;
        }
        let newValue = sender.isOn;
        Task {
            chat?.updateOptions({ (options) in
                options.notifications = newValue ? .none : .always;
            });
            if let pushModule = XmppService.instance.getClient(for: account)?.module(.push) as? SiskinPushNotificationsModule, let pushSettings = AccountManager.account(for: account)?.push {
                try await pushModule.enable(settings: pushSettings);
            }
        }
    }
    
    static func copyToPasteboard(address: VCard.Address) {
        var parts = [String]();
        if let street = address.street {
            parts.append(street);
        }
        var localityLine = "";
        if let postalCode = address.postalCode {
            localityLine.append(postalCode);
        }
        if let locality = address.locality {
            if !localityLine.isEmpty {
                localityLine.append(" ")
            }
            localityLine.append(locality)
        }
        if !localityLine.isEmpty {
            parts.append(localityLine);
        }
        if let region = address.region {
            parts.append(region);
        }
        if let country = address.country {
            parts.append(country);
        }
        UIPasteboard.general.string = parts.joined(separator: "\n");
    }
    
    static func openInMaps(address: VCard.Address) {
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
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch sections[indexPath.section] {
        case .phones:
            let phone = phones[indexPath.row];
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
                return UIMenu(title: "", options: [], children: [
                    UIAction(title: "Call", image: UIImage(systemName: "phone"), handler: { action in
                        if let url = URL(string: "tel:" + phone.number!) {
                            UIApplication.shared.open(url);
                        }
                    }),
                    UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc"), handler: { action in
                        UIPasteboard.general.string = phone.number;
                    })
                ])
            })
        case .emails:
            let email = emails[indexPath.row];
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
                return UIMenu(title: "", options: [], children: [
                    UIAction(title: "Send email", image: UIImage(systemName: "mail"), handler: { action in
                        if let url = URL(string: "mailto:" + email.address!) {
                            UIApplication.shared.open(url);
                        }
                    }),
                    UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc"), handler: { action in
                        UIPasteboard.general.string = email.address;
                    })
                ])
            })
        case .addresses:
            let address = addresses[indexPath.row];
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
                return UIMenu(title: "", options: [], children: [
                    UIAction(title: "Open in maps", image: UIImage(systemName: "map"), handler: { action in
                        ContactViewController.openInMaps(address: address);
                    }),
                    UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc"), handler: { action in
                        ContactViewController.copyToPasteboard(address: address);
                    })
                ])
            })
        default:
            return nil;
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

    internal class ContactMessageEncryptionItem: TablePickerViewItemsProtocol {
        
        public static func description(of value: ChatEncryption?) -> String {
            guard value != nil else {
                return NSLocalizedString("Default", comment: "encryption default label");
            }
            switch value! {
            case .omemo:
                return NSLocalizedString("OMEMO", comment: "encryption type");
            case .none:
                return NSLocalizedString("None", comment: "encryption type");
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
                return NSLocalizedString("Settings", comment: "contact details section");
            case .attachments:
                return "";
            case .encryption:
                return NSLocalizedString("Encryption", comment: "contact details section");
            case .phones:
                return NSLocalizedString("Phones", comment: "contact details section");
            case .emails:
                return NSLocalizedString("Emails", comment: "contact details section");
            case .addresses:
                return NSLocalizedString("Addresses", comment: "contact details section");
            }
        }
    }
    
    enum SettingsOptions: Int {
        case mute = 0
        case block = 1
    }
    
}
