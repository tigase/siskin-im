//
// AccountConnectivitySettingsViewController.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import UIKit

class AccountConnectivitySettingsViewController: UITableViewController {
    
    @IBOutlet var disableTls13Cell: UITableViewCell?;
    @IBOutlet var useDirectTlsCell: UITableViewCell?;
    
    @IBOutlet var hostField: UITextField?;
    @IBOutlet var portField: UITextField?;
    private var disableTls13Switch = UISwitch();
    private var useDirectTlsSwitch = UISwitch();

    var values: Settings?;
    
    override func viewDidLoad() {
        self.disableTls13Cell!.accessoryView = disableTls13Switch;
        self.useDirectTlsCell!.accessoryView = useDirectTlsSwitch;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        hostField?.text = values?.host;
        if let port = values?.port {
            portField?.text = String(port);
        } else {
            portField?.text = nil;
        }
        useDirectTlsSwitch.isOn = values?.useDirectTLS ?? false;
        disableTls13Switch.isOn = values?.disableTLS13 ?? false;
        updateUseDirectTLS();
        super.viewWillAppear(animated);
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
        values?.host = hostField?.text;
        values?.port = Int(portField?.text ?? "");
        values?.useDirectTLS = (values?.host != nil && values?.port != nil) && useDirectTlsSwitch.isOn;
        values?.disableTLS13 = disableTls13Switch.isOn;
    }
    
    @IBAction func textFieldDidChange(_ sender: Any) {
        updateUseDirectTLS()
    }
    
    func updateUseDirectTLS() {
        self.useDirectTlsSwitch.isEnabled = !((hostField?.text?.isEmpty ?? true) || (portField?.text?.isEmpty ?? true));
    }
    
    class Settings {
        var host: String?;
        var port: Int?;
        var useDirectTLS: Bool = false;
        var disableTLS13: Bool = false;
    }
    
}
