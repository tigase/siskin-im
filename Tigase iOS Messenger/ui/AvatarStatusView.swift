//
// AvatarStatusView.swift
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

class AvatarStatusView: UIView {
    
    @IBOutlet var avatarImageView: AvatarView!
    @IBOutlet var statusImageView: UIImageView!
    
    override var backgroundColor: UIColor? {
        get {
            return super.backgroundColor;
        }
        set {
            super.backgroundColor = newValue;
            statusImageView?.backgroundColor = newValue;
        }
    }
    
    /*
    // Only override drawRect: if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func drawRect(rect: CGRect) {
        // Drawing code
    }
    */

    override func awakeFromNib() {
        super.awakeFromNib();
        //avatarImageView.image = UIImage(named: "first");
        updateCornerRadius();
    }
    
    func updateAvatar(manager: AvatarManager, for account: BareJID, with: BareJID?, name: String?, orDefault defAvatar: UIImage) {
        self.avatarImageView.updateAvatar(manager: manager, for: account, with: with, name: name, orDefault: defAvatar);
    }
    
//    func setAvatar(_ avatar: UIImage?) {
//        self.avatarImageView.image = avatar;
//    }
    func resetAvatar() {
        self.avatarImageView.resetAvatar();
    }
    
    func setStatus(_ status:Presence.Show?) {
        let image:UIImage? = AvatarStatusView.getStatusImage(status);

        statusImageView.image = image;
    }
    
    static func getStatusImage(_ status: Presence.Show?) -> UIImage? {
        // default color as for offline contact
        var image:UIImage? = UIImage(named: "presence_offline");
        if status != nil {
            switch status! {
            case .chat:
                image = UIImage(named: "presence_chat");
            case .online:
                image = UIImage(named: "presence_online")
            case .away:
                image = UIImage(named: "presence_away");
            case .xa:
                image = UIImage(named: "presence_xa");
            case .dnd:
                image = UIImage(named: "presence_dnd");
            }
        }
        return image;
    }
    
    static func drawStatusBorder(backgroundColor: UIColor, status: UIImage) -> UIImage {
        let scale = UIScreen.main.scale;
        let size = status.size;

//        if self.contentMode == .redraw || contentMode == .scaleAspectFill || contentMode == .scaleAspectFit || contentMode == .scaleToFill {
//            size.width = (size.width * scale);
//            size.height = (size.height * scale);
//        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale);
        print("size:", size, "scale:", scale);
        let ctx = UIGraphicsGetCurrentContext()!;

        let path = CGPath(ellipseIn: CGRect(origin: .zero, size: size), transform: nil);
        ctx.addPath(path);

        ctx.setFillColor(backgroundColor.cgColor);
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height));


        status.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height));

        let image = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();

        return image;
    }
    
    func drawStatusIcon(_ size: CGFloat, color:UIColor) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0);
        let ctx = UIGraphicsGetCurrentContext();
        ctx!.saveGState();
        
        let rect  = CGRect(x: 0, y: 0, width: size, height: size);
        ctx!.setFillColor(color.cgColor);
        ctx!.fillEllipse(in: rect);
        
        ctx!.restoreGState();
        let img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return img!;
    }
    
    override func layoutSubviews() {
        super.layoutSubviews();
        updateCornerRadius();
    }
    
    func updateCornerRadius() {
        avatarImageView.layer.masksToBounds = true;
        avatarImageView.layer.cornerRadius = self.frame.height / 2;
        statusImageView.layer.opacity = 1.0;
        statusImageView.layer.masksToBounds = true;
        statusImageView.layer.cornerRadius = self.statusImageView.frame.height / 2;
    }
    
}
