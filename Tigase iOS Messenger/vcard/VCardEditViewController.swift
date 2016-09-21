//
// VCardEditViewController.swift
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

class VCardEditViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    let picker = UIImagePickerController();

    var xmppService: XmppService {
        let delegate = UIApplication.shared.delegate as! AppDelegate;
        return delegate.xmppService;
    }
    
    var account: String! {
        didSet {
            accountJid = BareJID(account);
        }
    }
    
    var accountJid: BareJID!;
    var vcard: VCardModule.VCard! {
        didSet {
            phones = [];
            vcard.telephones.forEach { (telephone) in
                let types = telephone.types;
                if types.isEmpty {
                    telephone.types = [VCardModule.VCard.EntryType.HOME];
                }
                telephone.types.forEach({ (type) in
                    let phone = VCardModule.VCard.Telephone()!;
                    phone.types = [type];
                    phone.number = telephone.number;
                    phones.append(phone);
                });
            };
            addresses = [];
            vcard.addresses.forEach { (address) in
                let types = address.types;
                if types.isEmpty {
                    address.types = [VCardModule.VCard.EntryType.HOME];
                }
                address.types.forEach({ (type) in
                    let addr = VCardModule.VCard.Address()!;
                    addr.types = [type];
                    addr.country = address.country;
                    addr.locality = address.locality;
                    addr.postalCode = address.postalCode;
                    addr.region = address.region;
                    addr.street = address.street;
                    addresses.append(addr);
                });
            }
            emails = [];
            vcard.emails.forEach { (email) in
                let types = email.types;
                if types.isEmpty {
                    email.types = [VCardModule.VCard.EntryType.HOME];
                }
                email.types.forEach({ (type) in
                    let e = VCardModule.VCard.Email()!;
                    e.types = [type];
                    e.address = email.address;
                    emails.append(e);
                });
            }
        }
    }
    
    //var telephones = TelephonesDataSource();
    
    var phones: [VCardModule.VCard.Telephone]!;
    var addresses: [VCardModule.VCard.Address]!;
    var emails: [VCardModule.VCard.Email]!;
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        vcard = xmppService.dbVCardsCache.getVCard(accountJid) ?? VCardModule.VCard();
        if vcard != nil {
            tableView.reloadData();
        }

        tableView.isEditing = true;
        tableView.separatorStyle = .none;
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
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "BasicInfoCell") as! VCardEditBasicTableViewCell;
            cell.avatarManager = xmppService.avatarManager;
            cell.accountJid = accountJid;
            cell.vcard = vcard;
            
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(VCardEditViewController.photoClicked));
            cell.photoView.addGestureRecognizer(singleTap);
            cell.photoView.isMultipleTouchEnabled = true;
            cell.photoView.isUserInteractionEnabled = true;
            
            return cell;
        case 1:
            if indexPath.row < phones.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "PhoneEditCell") as! VCardEditPhoneTableViewCell;
                cell.phone = phones[indexPath.row];
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "PhoneAddCell");
                return cell!;
            }
        case 2:
            if indexPath.row < emails.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "EmailEditCell") as! VCardEditEmailTableViewCell;
                cell.email = emails[indexPath.row];
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "EmailAddCell");
                return cell!;
            }
        case 3:
            if indexPath.row < addresses.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddressEditCell") as! VCardEditAddressTableViewCell;
                cell.address = addresses[indexPath.row];
                return cell;
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddressAddCell");
                return cell!;
            }
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PhoneAddCell");
            return cell!;
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch indexPath.section {
        case 0:
            return false;
        case 1:
            return indexPath.row < phones.count;
        case 2:
            return indexPath.row < emails.count;
        case 3:
            return indexPath.row < addresses.count;
        default:
            return false;
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1;
        case 1:
            return phones.count + 1;
        case 2:
            return emails.count + 1;
        case 3:
            return addresses.count + 1;
        default:
            return 0;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return nil;
        case 1:
            return "Phones";
        case 2:
            return "Emails";
        case 3:
            return "Addresses";
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0:
            return 234;
        case 3:
            return addresses.count == indexPath.row ? 44 : 122;
        default:
            return 44;
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        switch indexPath.section {
        case 0:
            return;
        case 1:
            if indexPath.row == phones.count {
                phones.append(VCardModule.VCard.Telephone()!);
                tableView.reloadData();
            }
            return;
        case 2:
            if indexPath.row == emails.count {
                emails.append(VCardModule.VCard.Email()!);
                tableView.reloadData();
            }
        case 3:
            if indexPath.row == addresses.count {
                addresses.append(VCardModule.VCard.Address()!);
                tableView.reloadData();
            }
            return;
        default:
            return;
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCellEditingStyle.delete {
            if indexPath.section == 1 {
                phones.remove(at: indexPath.row);
                tableView.reloadData();
            }
            if indexPath.section == 2 {
                emails.remove(at: indexPath.row);
                tableView.reloadData();
            }
            if indexPath.section == 3 {
                addresses.remove(at: indexPath.row);
                tableView.reloadData();
            }
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4;
    }
    
    @IBAction func refreshVCard(_ sender: UIBarButtonItem) {
        DispatchQueue.global(qos: .default).async {
            if let client = self.xmppService.getClient(self.accountJid) {
                if let vcardModule: VCardModule = client.modulesManager.getModule(VCardModule.ID) {
                    vcardModule.retrieveVCard(onSuccess: { (vcard) in
                        DispatchQueue.global(qos: .default).async() {
                            self.xmppService.dbVCardsCache.updateVCard(self.accountJid, vcard: vcard);
                            self.vcard = vcard;
                            DispatchQueue.main.async() {
                                self.tableView.reloadData();
                            }
                        }
                        }, onError: { (errorCondition) in
                    });
                }
            }
        }
    }
    
    @IBAction func publishVCard(_ sender: UIBarButtonItem) {
        vcard.telephones = phones;
        vcard.emails = emails;
        vcard.addresses = addresses;
        DispatchQueue.global(qos: .default).async {
        if let client = self.xmppService.getClient(self.accountJid) {
            if let vcardModule: VCardModule = client.modulesManager.getModule(VCardModule.ID) {
                vcardModule.publishVCard(self.vcard, onSuccess: {
                    DispatchQueue.main.async() {
                        _ = self.navigationController?.popViewController(animated: true);
                    }
                    
                    let avatarHash = Digest.sha1.digestToHex(self.vcard.photoValBinary);
                    let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID)!;
                    let x = Element(name: "x", xmlns: "vcard-temp:x:update");
                    let photo = Element(name: "photo");
                    photo.value = avatarHash;
                    x.addChild(photo);
                    presenceModule.setPresence(.online, status: nil, priority: nil, additionalElements: [x]);
                    }, onError: { (errorCondition) in
                        print("VCard publication failed", errorCondition);
                });
            }
        }
        }
    }
    
    func photoClicked() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { (action) in
                self.selectPhoto(.camera);
            }));
            alert.addAction(UIAlertAction(title: "Select photo", style: .default, handler: { (action) in
                self.selectPhoto(.photoLibrary);
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            present(alert, animated: true, completion: nil);
        } else {
            selectPhoto(.photoLibrary);
        }
    }
    
    func selectPhoto(_ source: UIImagePickerControllerSourceType) {
        picker.delegate = self;
        picker.allowsEditing = true;
        picker.sourceType = source;
        present(picker, animated: true, completion: nil);
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingImage image: UIImage, editingInfo: [String : AnyObject]?) {
        var photo = (editingInfo?[UIImagePickerControllerEditedImage] as? UIImage) ?? image;
        
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
        if let data = UIImagePNGRepresentation(photo) {
            vcard.photoValBinary = data;
            vcard.photoType = "image/png";
        }
        tableView.reloadData();
        picker.dismiss(animated: true, completion: nil);
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil);
    }
}
