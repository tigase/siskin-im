//
// SetupViewController.swift
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

class SetupViewController: UIViewController {
    
    @IBOutlet var appLogoView: UIImageView!;
    
    @IBOutlet var titleView: UILabel!;
    @IBOutlet var subtitleView: UILabel!;
    
    @IBOutlet var createAccountBtn: UIButton!
    @IBOutlet var existingAccountBtn: UIButton!
    
    override func viewDidLoad() {
        createAccountBtn.backgroundColor = self.view.tintColor;
        createAccountBtn.layer.borderWidth = 1;
        //createAccountBtn.layer.cornerRadius = createAccountBtn.frame.height / 2;
        createAccountBtn.layer.borderColor = UIColor.white.cgColor;
        createAccountBtn.setTitleColor(UIColor.white, for: .normal);
        
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged(_:)), name: UIDevice.orientationDidChangeNotification, object: nil);
        
        createAccountBtn.backgroundColor = self.subtitleView.textColor;
        existingAccountBtn.setTitleColor(self.subtitleView.textColor, for: .normal);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        appLogoView.layer.masksToBounds = true;
        orientationChanged();
    }
    
    @objc func orientationChanged(_ notification: Notification) {
        orientationChanged();
    }
    
    func orientationChanged() {
        createAccountBtn.layer.cornerRadius = createAccountBtn.frame.height / 2;
        appLogoView.layer.cornerRadius = appLogoView.frame.width / 8;
    }
    
    @IBAction func createAccountBtnClicked(_ sender: AnyObject) {
        let navigationController = storyboard!.instantiateViewController(withIdentifier: "RegisterAccountController") as! UINavigationController;
        let addAccountController = navigationController.visibleViewController! as! RegisterAccountController;
        addAccountController.hidesBottomBarWhenPushed = true;
        addAccountController.onAccountAdded = {
            (UIApplication.shared.delegate as? AppDelegate)?.hideSetupGuide()
        }
        navigationController.view.backgroundColor = UIColor.white;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    @IBAction func existingAccountBtnClicked(_ sender: AnyObject) {
        let navigationController = storyboard!.instantiateViewController(withIdentifier: "AddAccountController") as! UINavigationController;
        let addAccountController = navigationController.visibleViewController! as! AddAccountController;
        addAccountController.hidesBottomBarWhenPushed = true;
        addAccountController.onAccountAdded = {
            (UIApplication.shared.delegate as? AppDelegate)?.hideSetupGuide()
        }
        navigationController.view.backgroundColor = UIColor.white;
        self.showDetailViewController(navigationController, sender: self);
    }

}
