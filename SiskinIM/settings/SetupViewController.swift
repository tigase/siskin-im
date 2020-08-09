//
// SetupViewController.swift
//
// Siskin IM
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

class SetupViewController: UIViewController {
    
    @IBOutlet var appLogoView: UIImageView!;
    
    @IBOutlet var titleView: UILabel!;
    @IBOutlet var subtitleView: UILabel!;
    
    @IBOutlet var createAccountBtn: UIButton!
    @IBOutlet var existingAccountBtn: UIButton!
    
    override func viewDidLoad() {
        createAccountBtn.layer.borderWidth = 1;
        //createAccountBtn.layer.cornerRadius = createAccountBtn.frame.height / 2;
        createAccountBtn.layer.borderColor = UIColor.white.cgColor;
        
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged(_:)), name: UIDevice.orientationDidChangeNotification, object: nil);
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
        let addAccountController = RegisterAccountController.instantiate(fromAppStoryboard: .Account);
        addAccountController.hidesBottomBarWhenPushed = true;
        let navigationController = UINavigationController(rootViewController: addAccountController);
        self.showDetailViewController(navigationController, sender: self);
    }
    
    @IBAction func existingAccountBtnClicked(_ sender: AnyObject) {
        let addAccountController = AddAccountController.instantiate(fromAppStoryboard: .Account);
        addAccountController.hidesBottomBarWhenPushed = true;
        let navigationController = UINavigationController(rootViewController: addAccountController);
        self.showDetailViewController(navigationController, sender: self);
    }

}
