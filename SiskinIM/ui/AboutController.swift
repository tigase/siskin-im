//
// AboutController.swift
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

class AboutController: UIViewController {
    
    @IBOutlet var logoView: UIImageView!;
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var versionLabel: UILabel!;
    @IBOutlet var copyrightTextView: UITextView!;
    
    override func viewDidLoad() {
        logoView.layer.cornerRadius = 8;
        logoView.layer.masksToBounds = true;
        versionLabel.text = String.localizedStringWithFormat(NSLocalizedString("Version: %@", comment: "version of the app"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown");        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
    }
    
}
