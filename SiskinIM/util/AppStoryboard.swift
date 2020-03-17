//
// AppStoryboard.swift
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

enum AppStoryboard: String {
    case Main = "Main"
    case VoIP = "VoIP"
    case Groupchat = "Groupchat"
    case Info = "Info"
    case Settings = "Settings"
    case Account = "Account"
    
    var instance: UIStoryboard {
        return UIStoryboard(name: self.rawValue, bundle: Bundle.main);
    }
    
    func instantiateViewController(withIdentifier identifier: String) -> UIViewController {
        return instance.instantiateViewController(withIdentifier: identifier);
    }
    
    func instantiateViewController<T: UIViewController>(ofClass: T.Type) -> T {
        let storyboardID = ofClass.storyboardID;
        return instance.instantiateViewController(withIdentifier: storyboardID) as! T;
    }
}

extension UIViewController {
    
    class var storyboardID: String {
        return "\(self)";
    }
 
    static func instantiate(fromAppStoryboard: AppStoryboard) -> Self {
        return fromAppStoryboard.instantiateViewController(ofClass: self);
    }
    
}
