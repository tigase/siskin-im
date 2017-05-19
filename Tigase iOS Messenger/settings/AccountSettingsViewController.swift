//
// AccountSettingsViewController.swift
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

class AccountSettingsViewController: UITableViewController {
    
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
    
    @IBOutlet var avatarView: UIImageView!
    @IBOutlet var fullNameTextView: UILabel!
    @IBOutlet var companyTextView: UILabel!
    @IBOutlet var addressTextView: UILabel!
    
    @IBOutlet var enabledSwitch: UISwitch!
    @IBOutlet var pushNotificationSwitch: UISwitch!;
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        navigationItem.title = account;

        let config = AccountManager.getAccount(forJid: account);
        enabledSwitch.isOn = config?.active ?? false;
        pushNotificationSwitch.isOn = config?.pushNotifications ?? false;
        let client = xmppService.getClient(forJid: accountJid);
        let pushModule: TigasePushNotificationsModule? = client?.modulesManager.getModule(TigasePushNotificationsModule.ID);
        pushNotificationSwitch.isEnabled = (pushModule?.deviceId != nil) && (pushModule?.isAvailable ?? false);

        let vcard = xmppService.dbVCardsCache.getVCard(for: accountJid);
        update(vcard: vcard);

        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }
    
    override func viewDidAppear(_ animated: Bool) {
        //avatarView.sizeToFit();
        avatarView.layer.masksToBounds = true;
        avatarView.layer.cornerRadius = avatarView.frame.width / 2;
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.row == 0 && indexPath.section == 1 {
            return nil;
        }
        return indexPath;
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier != nil else {
            return;
        }
        switch segue.identifier! {
        case "EditAccountSegue":
            let destination = segue.destination as! AddAccountController;
            destination.account = account;
        case "EditAccountVCardSegue":
            let destination = segue.destination as! VCardEditViewController;
            destination.account = account;
        default:
            break;
        }
    }
        
    @IBAction func enabledSwitchChangedValue(_ sender: AnyObject) {
        if let config = AccountManager.getAccount(forJid: account) {
            config.active = enabledSwitch.isOn;
            AccountManager.updateAccount(config);
        }
    }
    
    @IBAction func pushNotificationSwitchChangedValue(_ sender: AnyObject) {
        if let config = AccountManager.getAccount(forJid: account) {
            config.pushNotifications = pushNotificationSwitch.isOn;
            AccountManager.updateAccount(config);
        }
    }
    
    
    func update(vcard: VCardModule.VCard?) {
        avatarView.image = xmppService.avatarManager.getAvatar(for: accountJid, account: accountJid);
        
        if let fn = vcard?.fn {
            fullNameTextView.text = fn;
        } else if let family = vcard?.familyName, let given = vcard?.givenName {
            fullNameTextView.text = "\(given) \(family)";
        } else {
            fullNameTextView.text = account;
        }
        
        let company = vcard?.orgName;
        let role = vcard?.role;
        if role != nil && company != nil {
            companyTextView.text = "\(role!) at \(company!)";
            companyTextView.isHidden = false;
        } else if company != nil {
            companyTextView.text = company;
            companyTextView.isHidden = false;
        } else if role != nil {
            companyTextView.text = role;
            companyTextView.isHidden = false;
        } else {
            companyTextView.isHidden = true;
        }
        
        let addresses = vcard?.addresses.filter { (addr) -> Bool in
            return !addr.isEmpty();
        };
        
        if let address = addresses?.first {
            var tmp = [String]();
            if address.street != nil {
                tmp.append(address.street!);
            }
            if address.locality != nil {
                tmp.append(address.locality!);
            }
            if address.country != nil {
                tmp.append(address.country!);
            }
            addressTextView.text = tmp.joined(separator: ", ");
        } else {
            addressTextView.text = nil;
        }
    }
}
