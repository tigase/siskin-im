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
import TigaseSwift

class VCardEditViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {
    
    let picker = UIImagePickerController();

    var xmppService: XmppService!;
        
    var account: BareJID!;
    var vcard: VCard!;
    
    var datePicker: UIDatePicker!;
    
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        vcard = xmppService.dbVCardsCache.getVCard(for: account) ?? VCard();
        if vcard != nil {
            tableView.reloadData();
        }

        tableView.isEditing = true;
        
        datePicker = UIDatePicker();
        datePicker.datePickerMode = .date;
        datePicker.addTarget(self, action: #selector(VCardEditViewController.bdayValueChanged), for: .valueChanged);
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
        switch VCardSections(rawValue: indexPath.section)! {
        case .basic:
            switch VCardBaseSectionRows(rawValue: indexPath.row)! {
            case .avatar:
                let cell = tableView.dequeueReusableCell(withIdentifier: "AvatarEditCell") as! VCardAvatarEditCell;
                cell.avatarView.set(name: nil, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                if let photo = vcard.photos.first {
                    xmppService.dbVCardsCache.fetchPhoto(photo: photo) { (photoData) in
                        DispatchQueue.main.async {
                            if let photoData = photoData, let image = UIImage(data: photoData) {
                                cell.avatarView.set(name: nil, avatar: image, orDefault: AvatarManager.instance.defaultAvatar);
                            } else {
                                cell.avatarView.set(name: nil, avatar: nil, orDefault: AvatarManager.instance.defaultAvatar);
                            }
                        }
                    }
                }
                cell.updateCornerRadius();
                return cell;
            case .givenName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = "Given name"
                cell.textField.text = vcard.givenName;
                cell.textField.delegate = self;
                cell.textField.tag = indexPath.row;
                return cell;
            case .familyName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = "Family name"
                cell.textField.text = vcard.surname;
                cell.textField.delegate = self;
                cell.textField.tag = indexPath.row;
                return cell;
            case .fullName:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = "Full name"
                cell.textField.text = vcard.fn;
                cell.textField.delegate = self;
                cell.textField.tag = indexPath.row;
                return cell;
            case .birthday:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = "Birthday"
                cell.textField.text = vcard.bday;
                cell.textField.inputView = self.datePicker;
                cell.textField.tag = indexPath.row;
                return cell;
            case .organization:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = "Organization"
                cell.textField.text = vcard.organizations.first?.name;
                cell.textField.delegate = self;
                cell.textField.tag = indexPath.row;
                return cell;
            case .organizationRole:
                let cell = tableView.dequeueReusableCell(withIdentifier: "TextEditCell") as! VCardTextEditCell;
                cell.textField.placeholder = "Organization role"
                cell.textField.text = vcard.role;
                cell.textField.delegate = self;
                cell.textField.tag = indexPath.row;
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
        switch VCardSections(rawValue: indexPath.section)! {
        case .basic:
            return false;
        case .phones:
            return indexPath.row < vcard.telephones.count;
        case .emails:
            return indexPath.row < vcard.emails.count;
        case .addresses:
            return indexPath.row < vcard.addresses.count;
        default:
            return false;
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 7;
        case 1:
            return vcard.telephones.count + 1;
        case 2:
            return vcard.emails.count + 1;
        case 3:
            return vcard.addresses.count + 1;
        default:
            return 0;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch VCardSections(rawValue: section)! {
        case .basic:
            return nil;
        case .phones:
            return "Phones";
        case .emails:
            return "Emails";
        case .addresses:
            return "Addresses";
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if VCardSections(rawValue: section)! == .basic {
            return 1.0;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        switch VCardSections(rawValue: indexPath.section)! {
        case .basic:
            if indexPath.row == VCardBaseSectionRows.avatar.rawValue {
                self.photoClicked();
            }
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
        default:
            return;
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            if indexPath.section == 1 {
                vcard.telephones.remove(at: indexPath.row);
                tableView.reloadData();
            }
            if indexPath.section == 2 {
                vcard.emails.remove(at: indexPath.row);
                tableView.reloadData();
            }
            if indexPath.section == 3 {
                vcard.addresses.remove(at: indexPath.row);
                tableView.reloadData();
            }
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4;
    }
    
    @IBAction func refreshVCard(_ sender: UIBarButtonItem) {
        DispatchQueue.global(qos: .default).async {
            self.xmppService.refreshVCard(account: self.account, for: self.account, onSuccess: { (vcard) in
                self.vcard = vcard;
                DispatchQueue.main.async() {
                    self.tableView.reloadData();
                }
            }, onError: { (errorCondition) in
            })
        }
    }
    
    @IBAction func publishVCard(_ sender: UIBarButtonItem) {
        self.tableView.endEditing(true);
        DispatchQueue.main.async {
            DispatchQueue.global(qos: .default).async {
                self.xmppService.publishVCard(account: self.account, vcard: self.vcard, completionHandler: {(result) in
                    switch result {
                    case .success(_):
                        DispatchQueue.main.async() {
                            _ = self.navigationController?.popViewController(animated: true);
                        }
                        self.xmppService.dbVCardsCache.updateVCard(for: self.account, on: self.account, vcard: self.vcard);
                        if let photo = self.vcard.photos.first {
                            self.xmppService.dbVCardsCache.fetchPhoto(photo: photo) { (data) in
                                guard data != nil, let client = self.xmppService.getClient(for: self.account) else {
                                    return;
                                }
                                let avatarHash = Digest.sha1.digest(toHex: data);
                                let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID)!;
                                let x = Element(name: "x", xmlns: "vcard-temp:x:update");
                                x.addChild(Element(name: "photo", cdata: avatarHash));
                                presenceModule.setPresence(show: .online, status: nil, priority: nil, additionalElements: [x]);
                            }
                        }
                    case .failure(let errorCondition):
                        let errorName = errorCondition.rawValue;
                        DispatchQueue.main.async {
                            self.tableView.setEditing(true, animated: true);
                            let alertController = UIAlertController(title: "Failure", message: "VCard publication failed.\n\(errorName)", preferredStyle: .alert);
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                            self.present(alertController, animated: true, completion: nil);
                        }
                        print("VCard publication failed", errorCondition);
                    }
                });
            }
        }
    }
    
    @objc func photoClicked() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { (action) in
                self.selectPhoto(.camera);
            }));
            alert.addAction(UIAlertAction(title: "Select photo", style: .default, handler: { (action) in
                self.selectPhoto(.photoLibrary);
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            let cell = self.tableView(tableView, cellForRowAt: IndexPath(row: VCardBaseSectionRows.avatar.rawValue, section: VCardSections.basic.rawValue)) as! VCardAvatarEditCell;
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
        guard var photo = (info[UIImagePickerController.InfoKey.editedImage] as? UIImage) else {
            print("no image available!");
            return;
        }
        
        // scalling photo to max of 180px
        var size: CGSize! = nil;
        if photo.size.height > photo.size.width {
            size = CGSize(width: (photo.size.width/photo.size.height) * 180, height: 180);
        } else {
            size = CGSize(width: 180, height: (photo.size.height/photo.size.width) * 180);
        }
        UIGraphicsBeginImageContextWithOptions(size, false, 0);
        photo.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height));
        photo = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        
        // saving photo
        let data = photo.pngData()
        if data != nil {
            vcard.photos = [VCard.Photo(type: "image/png", binval: data!.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)))];
        }
        tableView.reloadData();
        picker.dismiss(animated: true, completion: nil);
        
        if data != nil, let client = self.xmppService.getClient(forJid: self.account) {
            if let pepUserAvatarModule:PEPUserAvatarModule = client.modulesManager.getModule(PEPUserAvatarModule.ID) {
                if pepUserAvatarModule.isPepAvailable {
                    let question = UIAlertController(title: nil, message: "Do you wish to publish this photo as avatar?", preferredStyle: .actionSheet);
                    question.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action) in
                        pepUserAvatarModule.publishAvatar(data: data!, mimeType: "image/png", onSuccess: {
                            print("PEP: user avatar published");
                            }, onError: { (errorCondition, pubsubErrorCondition) in
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(title: "Error", message: "User avatar publication failed.\nReason: " + ((pubsubErrorCondition?.rawValue ?? errorCondition?.rawValue) ?? "unknown"), preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
                                    self.present(alert, animated: true, completion: nil);
                                }
                                print("PEP: user avatar publication failed", errorCondition ?? "nil", pubsubErrorCondition ?? "nil");
                        })
                    }));
                    question.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                    let cell = self.tableView(tableView, cellForRowAt: IndexPath(row: VCardBaseSectionRows.avatar.rawValue, section: VCardSections.basic.rawValue)) as! VCardAvatarEditCell;
                    question.popoverPresentationController?.sourceView = cell.avatarView;
                    question.popoverPresentationController?.sourceRect = cell.avatarView!.bounds;

                    present(question, animated: true, completion: nil);
                }
            }
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
        if let cell = tableView.cellForRow(at: IndexPath(row: VCardBaseSectionRows.birthday.rawValue, section: VCardSections.basic.rawValue)) as? VCardTextEditCell {
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
            case .organization:
                vcard.organizations = (text?.isEmpty ?? true) ? [] : [VCard.Organization(name: text!, types: [.work])];
            case .organizationRole:
                vcard.role = text;
            default:
                break;
            }
        }
    }
    
    enum VCardSections: Int {
        case basic = 0
        case phones = 1
        case emails = 2
        case addresses = 3
    }
    
    enum VCardBaseSectionRows: Int {
        case avatar = 0
        case givenName = 1
        case familyName = 2
        case fullName = 3
        case birthday = 4
        case organization = 5
        case organizationRole = 6
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
