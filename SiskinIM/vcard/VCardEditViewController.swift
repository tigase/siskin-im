//
// VCardEditViewController.swift
//
// Siskin IMM
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
import CryptoKit

class VCardEditViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {
    
    let picker = UIImagePickerController();

    var client: XMPPClient!;
        
    var vcard: VCard = VCard() {
        didSet {
            tableView.reloadData();
        }
    }
    
    var datePicker: UIDatePicker!;
    
    private let sections: [VCardSections] = [ .basic, .organization, .phones, .emails, .addresses ];
    private let basicRows: [VCardBaseSectionRows] = [.avatar, .givenName, .familyName, .fullName, .birthday ];
    private let orgRows: [VCardOrgSectionRows] = [.organizationName, .organizationRole];
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.isEditing = true;
        
        datePicker = UIDatePicker();
        datePicker.datePickerMode = .date;
        datePicker.addTarget(self, action: #selector(VCardEditViewController.bdayValueChanged), for: .valueChanged);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        Task {
            guard let vcard = await DBVCardStore.instance.vcard(for: client.userBareJid) else {
                return;
            }
            await MainActor.run(body: {
                self.vcard = vcard;
            })
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
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .basic:
            let row = basicRows[indexPath.row];
            switch row {
            case .avatar:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AvatarEditCell") as! VCardAvatarEditCell;
                cell.avatarView.set(name: nil, avatar: nil);
                if let photo = vcard.photos.first {
                    Task {
                        let data = try await VCardManager.fetchPhoto(photo: photo);
                        DispatchQueue.main.async {
                            cell.avatarView.set(name: nil, avatar: UIImage(data: data));
                        }
                    }
                }
                cell.updateCornerRadius();
                return cell;
            case .givenName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = NSLocalizedString("Given name", comment: "vcard field label")
                cell.textField.text = vcard.givenName;
                cell.textField.delegate = self;
                cell.textField.tag = row.rawValue;
                return cell;
            case .familyName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = NSLocalizedString("Family name", comment: "vcard field label")
                cell.textField.text = vcard.surname;
                cell.textField.delegate = self;
                cell.textField.tag = row.rawValue;
                return cell;
            case .fullName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = NSLocalizedString("Full name", comment: "vcard field label")
                cell.textField.text = vcard.fn;
                cell.textField.delegate = self;
                cell.textField.tag = row.rawValue;
                return cell;
            case .birthday:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = NSLocalizedString("Birthday", comment: "vcard field label")
                cell.textField.text = vcard.bday;
                cell.textField.inputView = self.datePicker;
                cell.textField.tag = row.rawValue;
                return cell;
            }
        case .organization:
            let row = orgRows[indexPath.row];
            switch row {
            case .organizationName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = NSLocalizedString("Organization", comment: "vcard field label")
                cell.textField.text = vcard.organizations.first?.name;
                cell.textField.delegate = self;
                cell.textField.tag = row.rawValue;
                return cell;
            case .organizationRole:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = NSLocalizedString("Organization role", comment: "vcard field label")
                cell.textField.text = vcard.role;
                cell.textField.delegate = self;
                cell.textField.tag = row.rawValue;
                return cell;
            }
        case .phones:
            if indexPath.row < vcard.telephones.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "PhoneEditCell") as! VCardEditPhoneTableViewCell;
                cell.phone = vcard.telephones[indexPath.row];
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "PhoneAddCell");
                for subview in cell!.subviews {
                    for view in subview.subviews {
                        if let btn = view as? UIButton {
                            btn.isUserInteractionEnabled = false;
                        }
                    }
                }
                return cell!;
            }
        case .emails:
            if indexPath.row < vcard.emails.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "EmailEditCell") as! VCardEditEmailTableViewCell;
                cell.email = vcard.emails[indexPath.row];
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "EmailAddCell");
                for subview in cell!.subviews {
                    for view in subview.subviews {
                        if let btn = view as? UIButton {
                            btn.isUserInteractionEnabled = false;
                        }
                    }
                }
                return cell!;
            }
        case .addresses:
            if indexPath.row < vcard.addresses.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddressEditCell") as! VCardEditAddressTableViewCell;
                cell.address = vcard.addresses[indexPath.row];
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddressAddCell");
                for subview in cell!.subviews {
                    for view in subview.subviews {
                        if let btn = view as? UIButton {
                            btn.isUserInteractionEnabled = false;
                        }
                    }
                }
                return cell!;
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? VCardAvatarEditCell)?.updateCornerRadius();
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch sections[indexPath.section] {
        case .basic:
            return false;
        case .organization:
            return false;
        case .phones:
            return indexPath.row < vcard.telephones.count;
        case .emails:
            return indexPath.row < vcard.emails.count;
        case .addresses:
            return indexPath.row < vcard.addresses.count;
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return basicRows.count;
        case 1:
            return orgRows.count;
        case 2:
            return vcard.telephones.count + 1;
        case 3:
            return vcard.emails.count + 1;
        case 4:
            return vcard.addresses.count + 1;
        default:
            return 0;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .basic:
            return nil;
        case .organization:
            return NSLocalizedString("Organization", comment: "vcard section label")
        case .phones:
            return NSLocalizedString("Phones", comment: "vcard section label");
        case .emails:
            return NSLocalizedString("Emails", comment: "vcard section label");
        case .addresses:
            return NSLocalizedString("Addresses", comment: "vcard section label");
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if sections[section] == .basic {
            return 1.0;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        switch sections[indexPath.section] {
        case .basic:
            if basicRows[indexPath.row] == .avatar {
                self.photoClicked();
            }
            return;
        case .organization:
            return;
        case .phones:
            if indexPath.row == vcard.telephones.count {
                vcard.telephones.append(VCard.Telephone(uri: nil, types: [.home]));
                tableView.reloadData();
            }
            return;
        case .emails:
            if indexPath.row == vcard.emails.count {
                vcard.emails.append(VCard.Email(address: nil, types: [.home]));
                tableView.reloadData();
            }
        case .addresses:
            if indexPath.row == vcard.addresses.count {
                vcard.addresses.append(VCard.Address(types: [.home]));
                tableView.reloadData();
            }
            return;
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            switch sections[indexPath.section] {
            case .phones:
                vcard.telephones.remove(at: indexPath.row);
                tableView.reloadData();
            case .emails:
                vcard.emails.remove(at: indexPath.row);
                tableView.reloadData();
            case .addresses:
                vcard.addresses.remove(at: indexPath.row);
                tableView.reloadData();
            default:
                break;
            }
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count;
    }
    
    @IBAction func refreshVCard(_ sender: UIBarButtonItem) {
        Task {
            let vcard = try await VCardManager.instance.refreshVCard(for: client.userBareJid, on: client.userBareJid);
            DispatchQueue.main.async {
                self.vcard = vcard;
            }
        }
    }
    
    @IBAction func publishVCard(_ sender: UIBarButtonItem) {
        self.tableView.endEditing(true);
        DispatchQueue.main.async {
            let vcard = self.vcard;
            Task {
                do {
                    try await self.publishVCard(vcard: vcard);
                    DispatchQueue.main.async() {
                        _ = self.navigationController?.popViewController(animated: true);
                    }
                    DBVCardStore.instance.updateVCard(for: self.client.userBareJid, on: self.client.userBareJid, vcard: vcard);
                    if let photo = vcard.photos.first, let data = try? await VCardManager.fetchPhoto(photo: photo) {
                        let avatarHash = Insecure.SHA1.hash(toHex: data);
                        let x = Element(name: "x", xmlns: "vcard-temp:x:update");
                        x.addChild(Element(name: "photo", cdata: avatarHash));
                        try? await self.client.module(.presence).setPresence(show: .online, status: nil, priority: nil, additionalElements: [x]);
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.tableView.setEditing(true, animated: true);
                        let alertController = UIAlertController(title: NSLocalizedString("Failure", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("VCard publication failed: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self.present(alertController, animated: true, completion: nil);
                    }
                }
            }
        }
    }
    
    private func publishVCard(vcard: VCard) async throws {
        do {
            try await client.module(.vcard4).publish(vcard: vcard)
        } catch {
            guard ((error as? XMPPError ?? .undefined_condition).condition.type == .wait) else {
                try await client.module(.vcardTemp).publish(vcard: vcard);
                return;
            }
            throw error;
        }
    }
        
    @objc func photoClicked() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Take photo", comment: "photo selection action"), style: .default, handler: { (action) in
                self.selectPhoto(.camera);
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Select photo", comment: "photo selection action"), style: .default, handler: { (action) in
                self.selectPhoto(.photoLibrary);
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
            let cell = self.tableView(tableView, cellForRowAt: IndexPath(row: basicRows.firstIndex(of: .avatar) ?? 0, section: sections.firstIndex(of: .basic) ?? 0)) as! VCardAvatarEditCell;
            alert.popoverPresentationController?.sourceView = cell.avatarView;
            alert.popoverPresentationController?.sourceRect = cell.avatarView!.bounds;
            present(alert, animated: true, completion: nil);
        } else {
            selectPhoto(.photoLibrary);
        }
    }
    
    func selectPhoto(_ source: UIImagePickerController.SourceType) {
        picker.delegate = self;
        picker.allowsEditing = true;
        picker.sourceType = source;
        present(picker, animated: true, completion: nil);
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let photo = (info[UIImagePickerController.InfoKey.editedImage] as? UIImage) else {
            return;
        }
        
        guard let pngImage = photo.scaled(maxWidthOrHeight: 48), let pngData = pngImage.pngData() else {
            return;
        }
        
        var items: [PEPUserAvatarModule.Avatar] = [.init(data: pngData, mimeType: "image/png", width: Int(pngImage.size.width), height: Int(pngImage.size.height))];
        
        if let jpegImage = photo.scaled(maxWidthOrHeight: 256), let jpegData = jpegImage.jpegData(compressionQuality: 0.8) {
            items = [.init(data: jpegData, mimeType: "image/jpeg", width: Int(jpegImage.size.width), height: Int(jpegImage.size.height))] + items;
        }
                
        if let item = items.first {
            vcard.photos = [VCard.Photo(type: item.info.mimeType, binval: item.data!.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)))];
        }
        tableView.reloadData();
        picker.dismiss(animated: true, completion: nil);
        
        let pepUserAvatarModule = client.module(.pepUserAvatar);
        if pepUserAvatarModule.isPepAvailable {
            let question = UIAlertController(title: nil, message: NSLocalizedString("Do you wish to publish this photo as avatar?", comment: "alert body"), preferredStyle: .actionSheet);
            question.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .default, handler: { (action) in
                Task {
                    do {
                        _ = try await pepUserAvatarModule.publishAvatar(avatar: items);
                    } catch {
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("User avatar publication failed.\nReason: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
                            self.present(alert, animated: true, completion: nil);
                        }
                    }
                }
            }));
            question.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .cancel, handler: nil));
            let cell = self.tableView(tableView, cellForRowAt: IndexPath(row: basicRows.firstIndex(of: .avatar) ?? 0, section: sections.firstIndex(of: .basic) ?? 0)) as! VCardAvatarEditCell;
            question.popoverPresentationController?.sourceView = cell.avatarView;
            question.popoverPresentationController?.sourceRect = cell.avatarView!.bounds;
            
            present(question, animated: true, completion: nil);
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil);
    }
    
    @objc func bdayValueChanged(_ sender: UIDatePicker) {
        let formatter = DateFormatter();
        formatter.timeStyle = .none;
        formatter.dateFormat = "yyyy-MM-dd";
        let string = formatter.string(from: sender.date);
        if let cell = tableView.cellForRow(at: IndexPath(row: basicRows.firstIndex(of: .birthday) ?? 0, section: sections.firstIndex(of: .basic) ?? 0)) as? VCardTextEditCell {
            cell.textField.text = string;
        }
        vcard.bday = string;
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        let text = textField.text;
        if let row = VCardBaseSectionRows(rawValue: textField.tag) {
            switch row {
            case .givenName:
                vcard.givenName = text;
            case .familyName:
                vcard.surname = text;
            case .fullName:
                vcard.fn = text;
            default:
                break;
            }
        }
        if let row = VCardOrgSectionRows(rawValue: textField.tag) {
            switch row {
            case .organizationName:
                vcard.organizations = (text?.isEmpty ?? true) ? [] : [VCard.Organization(name: text!, types: [.work])];
            case .organizationRole:
                vcard.role = text;
            default:
                break;
            }
        }
    }
    
    enum VCardSections {
        case basic
        case organization
        case phones
        case emails
        case addresses
    }
    
    enum VCardBaseSectionRows: Int {
        case avatar = 0
        case givenName = 1
        case familyName = 2
        case fullName = 3
        case birthday = 4
    }
    
    enum VCardOrgSectionRows: Int {
        case organizationName = 10
        case organizationRole = 11
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
