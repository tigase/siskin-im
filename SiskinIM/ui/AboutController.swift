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
    
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var versionLabel: UILabel!;
    @IBOutlet var copyrightTextView: UITextView!;
    
    override func viewDidLoad() {
        versionLabel.text = "Version: \(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String ?? "Unknown")";
        
        copyrightTextView.textColor = Appearance.current.secondaryLabelColor;
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: Appearance.CHANGED, object: nil);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.updateAppearance();
    }
    
    @objc func appearanceChanged(_ notification: Notification) {
        self.updateAppearance();
    }
    
    func updateAppearance() {
        self.view.tintColor = Appearance.current.tintColor;
        
        self.view.backgroundColor = Appearance.current.systemBackground;
        self.nameLabel.textColor = Appearance.current.labelColor;
        self.versionLabel.textColor = Appearance.current.labelColor;
        self.copyrightTextView.backgroundColor = Appearance.current.systemBackground;
        self.copyrightTextView.textColor = Appearance.current.secondaryLabelColor;
        if let navController = self.navigationController {
            navController.navigationBar.barStyle = Appearance.current.navigationBarStyle;
            navController.navigationBar.tintColor = Appearance.current.navigationBarTintColor;
            navController.navigationBar.barTintColor = Appearance.current.controlBackgroundColor;
            navController.navigationBar.setNeedsLayout();
            navController.navigationBar.layoutIfNeeded();
            navController.navigationBar.setNeedsDisplay();
        }
    }
}
