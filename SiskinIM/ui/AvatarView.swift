//
// AvatarStatusView.swift
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
import TigaseSwift

class AvatarView: UIImageView {
    
    private var name: String? {
        didSet {
            if let parts = name?.uppercased().components(separatedBy: CharacterSet.letters.inverted) {
                let first = parts.first?.first;
                let last = parts.count > 1 ? parts.last?.first : nil;
                self.initials = (last == nil || first == nil) ? (first == nil ? nil : "\(first!)") : "\(first!)\(last!)";
            } else {
                self.initials = nil;
            }
            self.setNeedsDisplay();
        }
    }
//    override var image: UIImage? {
//        get {
//            return super.image;
//        }
//        set {
//            //if image != nil {
//            //    self.image = prepareInitialsAvatar();
//            //}
//            if newValue != nil {
//                super.image = newValue;
//            } else if let initials = self.initials {
//                super.image = prepareInitialsAvatar(for: initials);
//            } else {
//                super.image = nil;
//            }
//        }
//    }
    fileprivate(set) var initials: String?;
    
    func set(name: String?, avatar: UIImage?, orDefault defAvatar: UIImage) {
        self.name = name;
        if avatar != nil {
            self.image = avatar;
        } else if self.name != nil {
            if self.name != name {
                self.name = name;
            }
            if let initials = self.initials {
                self.image = self.prepareInitialsAvatar(for: initials);
            } else {
                 self.image = defAvatar;
            }
        } else {
             self.image = defAvatar;
        }
    }
        
    func prepareInitialsAvatar(for text: String) -> UIImage {
        let scale = UIScreen.main.scale;
        var size = self.bounds.size;
        
        if self.contentMode == .redraw || contentMode == .scaleAspectFill || contentMode == .scaleAspectFit || contentMode == .scaleToFill {
            size.width = (size.width * scale);
            size.height = (size.height * scale);
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale);
        let ctx = UIGraphicsGetCurrentContext()!;
        let path = CGPath(ellipseIn: self.bounds, transform: nil);
        ctx.addPath(path);
        
        
        ctx.setFillColor(UIColor.systemGray.cgColor);
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height));
        
        let textAttr: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white.withAlphaComponent(0.9), .font: UIFont.systemFont(ofSize: size.width * 0.4, weight: .medium)];
        let textSize = text.size(withAttributes: textAttr);
        
        text.draw(in: CGRect(x: size.width/2 - textSize.width/2, y: size.height/2 - textSize.height/2, width: textSize.width, height: textSize.height), withAttributes: textAttr);
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        
        return image;
    }
}
