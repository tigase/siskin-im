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

    @IBOutlet var avatarImageView: UIImageView!
    @IBOutlet var statusImageView: UIImageView!
    
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
        avatarImageView.layer.masksToBounds = true;
        avatarImageView.layer.cornerRadius = self.avatarImageView.frame.width / 2;
    }
    
    func setAvatar(avatar: UIImage?) {
        self.avatarImageView.image = avatar;
    }
    
    func setStatus(status:Presence.Show?) {
        var image:UIImage? = AvatarStatusView.getStatusImage(status);

        statusImageView.image = image;
    }
    
    static func getStatusImage(status: Presence.Show?) -> UIImage? {
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
    
    func drawStatusIcon(size: CGFloat, color:UIColor) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), false, 0);
        let ctx = UIGraphicsGetCurrentContext();
        CGContextSaveGState(ctx);
        
        let rect  = CGRectMake(0, 0, size, size);
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillEllipseInRect(ctx, rect);
        
        CGContextRestoreGState(ctx);
        let img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return img;
    }
    
}
