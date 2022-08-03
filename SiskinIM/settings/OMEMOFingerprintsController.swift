//
// OMEMOFingerprintsController.swift
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
import Martin
import MartinOMEMO

class OMEMOFingerprintsController: UITableViewController {
    
    var account: BareJID!;
    var localIdentity: Identity?;
    var otherIdentities: [Identity] = [];
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        let allIdentities = DBOMEMOStore.instance.identities(forAccount: account, andName: account.stringValue);
        let localDeviceId = Int32(bitPattern: AccountSettings.omemoRegistrationId(for: account) ?? 0);
        self.localIdentity = allIdentities.first(where: { (identity) -> Bool in
            return identity.address.deviceId == localDeviceId;
        })
        self.otherIdentities = allIdentities.filter({ (identity) -> Bool in
            return identity.address.deviceId != localDeviceId;
        });
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return localIdentity != nil ? 1 : 0;
        } else {
            return otherIdentities.count;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Fingerprint of this device", comment: "section label");
        default:
            return NSLocalizedString("Other devices fingerprints", comment: "section label");
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "OMEMOLocalIdentityCell", for: indexPath);
            (cell.contentView.subviews[1] as? UILabel)?.text = String.localizedStringWithFormat(NSLocalizedString("Device: %@", comment: "label for omemo device id"), "\(localIdentity?.address.deviceId ?? -1)");
            (cell.contentView.subviews[0] as? UILabel)?.text = preetify(fingerprint: localIdentity?.fingerprint);
            return cell;
        default:
            let identity = self.otherIdentities[indexPath.row];
            let cell = tableView.dequeueReusableCell(withIdentifier: "OMEMORemoteIdentityCell", for: indexPath) as! OMEMOIdentityTableViewCell;
            cell.deviceLabel?.text = String.localizedStringWithFormat(NSLocalizedString("Device: %@", comment: "label for omemo device id"), "\(identity.address.deviceId)");
            cell.identityLabel.text = preetify(fingerprint: identity.fingerprint);
            cell.trustSwitch.isEnabled = identity.status.isActive;
            cell.trustSwitch.isOn = identity.status.trust == .trusted || identity.status.trust == .undecided;
            let account = self.account!;
            cell.valueChangedListener = { (sender) in
                _ = DBOMEMOStore.instance.setStatus(identity.status.toTrust(sender.isOn ? .trusted : .compromised), forIdentity: identity.address, andAccount: account);
            }
            return cell;
        }
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1 else {
            return nil;
        }
        
        let account = self.account!;
        let identity = self.otherIdentities[indexPath.row];
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            return UIMenu(title: "", children: [
                UIAction(title: NSLocalizedString("Delete", comment: "button label"), image: UIImage(systemName: "trash"), attributes: .destructive, handler: { [weak self] action in
                    guard let omemoModule = XmppService.instance.getClient(for: account)?.module(.omemo) else {
                        return;
                    }
                                
                    omemoModule.removeDevices(withIds: [identity.address.deviceId]);
                    self?.otherIdentities.remove(at: indexPath.row);
                    self?.tableView.reloadData();
                })
            ])
        });
    }
    
    func preetify(fingerprint tmp: String?) -> String? {
        guard var fingerprint = tmp else {
            return nil;
        }
        fingerprint = String(fingerprint.dropFirst(2));
        var idx = fingerprint.startIndex;
        for _ in 0..<(fingerprint.count / 8) {
            idx = fingerprint.index(idx, offsetBy: 8);
            fingerprint.insert(" ", at: idx);
            idx = fingerprint.index(after: idx);
        }
        return fingerprint;
    }
    
}
