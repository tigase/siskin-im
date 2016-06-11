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
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    var account: BareJID!;
    var jid: BareJID!;
    var vcard: VCardModule.VCard? {
        didSet {
            phones = [];
            vcard?.telephones.forEach { (telephone) in
                let types = telephone.types;
                let val = telephone.number?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet());
                guard val != nil && !val!.isEmpty else {
                    return;
                }
                if types.isEmpty {
                    telephone.types = [VCardModule.VCard.Type.HOME];
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
                    address.types = [VCardModule.VCard.Type.HOME];
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
                let val = email.address?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet());
                guard val != nil && !val!.isEmpty else {
                    return;
                }
                if types.isEmpty {
                    email.types = [VCardModule.VCard.Type.HOME];
                }
                email.types.forEach({ (type) in
                    let e = VCardModule.VCard.Email()!;
                    e.types = [type];
                    e.address = val;
                    emails.append(e);
                });
            }
            tableView.reloadData();
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
        vcard = xmppService.dbVCardsCache.getVCard(jid);
        if vcard == nil {
            refreshVCard();
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func refreshVCard(sender: UIBarButtonItem) {
        refreshVCard();
    }
    
    func refreshVCard() {
        if let vcardModule: VCardModule = xmppService.getClient(account)?.modulesManager.getModule(VCardModule.ID) {
            vcardModule.retrieveVCard(JID(jid), onSuccess: { (vcard) in
                self.xmppService.dbVCardsCache.updateVCard(self.jid, vcard: vcard);
                self.vcard = vcard;
                }, onError: { (errorCondition) in
                    // retrieval failed - ignoring for now
            })
        }
    }
    
    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
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
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
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
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
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
    
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        switch indexPath.section {
        case 0:
            return 76;
        case 3:
            return 80;
        default:
            return 51;
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCellWithIdentifier("BasicInfoCell", forIndexPath: indexPath) as! ContactBasicTableViewCell;
        
            cell.account = account;
            cell.jid = jid;
            cell.avatarManager = xmppService.avatarManager;
            cell.vcard = vcard;
        
            return cell;
        case 1:
            let cell = tableView.dequeueReusableCellWithIdentifier("ContactFormCell", forIndexPath: indexPath) as! ContactFormTableViewCell;
            let phone = phones[indexPath.row];
            let type = (phone.types.first ?? VCardModule.VCard.Type.HOME).rawValue.capitalizedString;
            
            cell.typeView.text = type;
            cell.labelView.text = phone.number?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet());
            
            return cell;
        case 2:
            let cell = tableView.dequeueReusableCellWithIdentifier("ContactFormCell", forIndexPath: indexPath) as! ContactFormTableViewCell;
            let email = emails[indexPath.row];
            let type = (email.types.first ?? VCardModule.VCard.Type.HOME).rawValue.capitalizedString;
            
            cell.typeView.text = type;
            cell.labelView.text = email.address?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet());
            
            return cell;
        case 3:
            let cell = tableView.dequeueReusableCellWithIdentifier("AddressCell", forIndexPath: indexPath) as! ContactFormTableViewCell;
            let address = addresses[indexPath.row];
            let type = (address.types.first ?? VCardModule.VCard.Type.HOME).rawValue.capitalizedString;
            
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
            let cell = tableView.dequeueReusableCellWithIdentifier("ContactFormCell", forIndexPath: indexPath) as! ContactFormTableViewCell;
            return cell;
        }
    }

    override func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        if indexPath.section == 0 {
            return nil;
        }
        return indexPath;
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        switch indexPath.section {
        case 1:
            if let url = NSURL(string: "tel:" + phones[indexPath.row].number!) {
                UIApplication.sharedApplication().openURL(url);
            }
        case 2:
            if let url = NSURL(string: "mailto:" + emails[indexPath.row].address!) {
                UIApplication.sharedApplication().openURL(url);
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
            let query = parts.joinWithSeparator(",").stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet())!;
            if let url = NSURL(string: "http://maps.apple.com/?q=" + query) {
                UIApplication.sharedApplication().openURL(url);
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
