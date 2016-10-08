//
// ContactViewController.swift
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

class ContactViewController: UITableViewController {

    var xmppService: XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    var account: BareJID!;
    var jid: BareJID!;
    var vcard: VCardModule.VCard? {
        didSet {
            phones = [];
            vcard?.telephones.forEach { (telephone) in
                let types = telephone.types;
                let val = telephone.number?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
                guard val != nil && !val!.isEmpty else {
                    return;
                }
                if types.isEmpty {
                    telephone.types = [VCardModule.VCard.EntryType.HOME];
                }
                telephone.types.forEach({ (type) in
                    let phone = VCardModule.VCard.Telephone()!;
                    phone.types = [type];
                    phone.number = val;
                    phones.append(phone);
                });
            };
            addresses = [];
            vcard?.addresses.forEach { (address) in
                if address.isEmpty() {
                    return;
                }
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
            vcard?.emails.forEach { (email) in
                let types = email.types;
                let val = email.address?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
                guard val != nil && !val!.isEmpty else {
                    return;
                }
                if types.isEmpty {
                    email.types = [VCardModule.VCard.EntryType.HOME];
                }
                email.types.forEach({ (type) in
                    let e = VCardModule.VCard.Email()!;
                    e.types = [type];
                    e.address = val;
                    emails.append(e);
                });
            }
            DispatchQueue.main.async() {
                self.tableView.reloadData();
            }
        }
    }
    
    var addresses: [VCardModule.VCard.Address]!;
    var phones: [VCardModule.VCard.Telephone]!;
    var emails: [VCardModule.VCard.Email]!;
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        vcard = xmppService.dbVCardsCache.getVCard(for: jid);
        if vcard == nil {
            refreshVCard();
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func refreshVCard(_ sender: UIBarButtonItem) {
        refreshVCard();
    }
    
    func refreshVCard() {
        DispatchQueue.global(qos: .background).async() {
            if let vcardModule: VCardModule = self.xmppService.getClient(forJid: self.account)?.modulesManager.getModule(VCardModule.ID) {
                vcardModule.retrieveVCard(from: JID(self.jid), onSuccess: { (vcard) in
                    DispatchQueue.global(qos: .background).async() {
                        self.xmppService.dbVCardsCache.updateVCard(for: self.jid, on: self.account, vcard: vcard);
                        self.vcard = vcard;
                    }
                    }, onError: { (errorCondition) in
                        // retrieval failed - ignoring for now
                })
            }
        }
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in: UITableView) -> Int {
        var i = 1;
        if phones.count > 0 {
            i += 1;
        }
        if emails.count > 0 {
            i += 1;
        }
        if addresses.count > 0 {
            i += 1;
        }
        return i;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1;
        case 1:
            return phones.count;
        case 2:
            return emails.count;
        case 3:
            return addresses.count;
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
            return 76;
        case 3:
            return 80;
        default:
            return 51;
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "BasicInfoCell", for: indexPath) as! ContactBasicTableViewCell;
        
            cell.account = account;
            cell.jid = jid;
            cell.avatarManager = xmppService.avatarManager;
            cell.vcard = vcard;
        
            return cell;
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath) as! ContactFormTableViewCell;
            let phone = phones[indexPath.row];
            let type = (phone.types.first ?? VCardModule.VCard.EntryType.HOME).rawValue.capitalized;
            
            cell.typeView.text = type;
            cell.labelView.text = phone.number?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            
            return cell;
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath) as! ContactFormTableViewCell;
            let email = emails[indexPath.row];
            let type = (email.types.first ?? VCardModule.VCard.EntryType.HOME).rawValue.capitalized;
            
            cell.typeView.text = type;
            cell.labelView.text = email.address?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            
            return cell;
        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddressCell", for: indexPath ) as! ContactFormTableViewCell;
            let address = addresses[indexPath.row];
            let type = (address.types.first ?? VCardModule.VCard.EntryType.HOME).rawValue.capitalized;
            
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
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactFormCell", for: indexPath as IndexPath) as! ContactFormTableViewCell;
            return cell;
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
        switch indexPath.section {
        case 1:
            if let url = URL(string: "tel:" + phones[indexPath.row].number!) {
                UIApplication.shared.openURL(url);
            }
        case 2:
            if let url = URL(string: "mailto:" + emails[indexPath.row].address!) {
                UIApplication.shared.openURL(url);
            }
        case 3:
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
                UIApplication.shared.openURL(url);
            }
        default:
            break;
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

}
