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
import Martin

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
            self.updateImage();
        }
    }
    
    var avatar: UIImage? {
        didSet {
            updateImage();
        }
    }
    
    override var frame: CGRect {
        didSet {
            self.layer.cornerRadius = min(frame.width, frame.height) / 2;
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews();
        self.layer.cornerRadius = min(frame.width, frame.height) / 2;
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
    
    private func updateImage() {
        if avatar != nil {
            // workaround to properly handle appearance
//            if self.avatar! == AvatarManager.instance.defaultGroupchatAvatar {
                self.image = self.avatar;
//            } else {
//                self.image = avatar?.square(max(self.frame.size.width, self.frame.size.height));
//            }
        } else if let initials = self.initials {
            self.image = self.prepareInitialsAvatar(for: initials);
        } else {
            self.image = AvatarManager.instance.defaultAvatar;
        }
    }
    
    func set(name: String?, avatar: UIImage?) {
        self.name = name;
        self.avatar = avatar;
        self.setNeedsDisplay();
    }
        
    func prepareInitialsAvatar(for text: String) -> UIImage? {
        let scale = UIScreen.main.scale;
        var size = self.bounds.size;
        
        if self.contentMode == .redraw || contentMode == .scaleAspectFill || contentMode == .scaleAspectFit || contentMode == .scaleToFill {
            size.width = (size.width * scale);
            size.height = (size.height * scale);
        }
        
        guard size.width > 0 && size.height > 0 else {
            return nil;
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale);
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext();
            return nil;
        }
        let path = CGPath(ellipseIn: self.bounds, transform: nil);
        ctx.addPath(path);
                
        let colors = [UIColor.systemGray.adjust(brightness: 0.52).cgColor, UIColor.systemGray.adjust(brightness: 0.48).cgColor];
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!;
        ctx.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: 0, y: size.height), options: []);
//        ctx.setFillColor(UIColor.systemGray.cgColor);
//        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height));
        
        let textAttr: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white.withAlphaComponent(0.9), .font: UIFont.systemFont(ofSize: size.width * 0.4, weight: .medium)];
        let textSize = text.size(withAttributes: textAttr);
        
        text.draw(in: CGRect(x: size.width/2 - textSize.width/2, y: size.height/2 - textSize.height/2, width: textSize.width, height: textSize.height), withAttributes: textAttr);
        
        let image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return image;
    }
    
}
