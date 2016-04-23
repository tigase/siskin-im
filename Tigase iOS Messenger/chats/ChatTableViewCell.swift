//
// ChatTableViewCell.swift
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

class ChatTableViewCell: UITableViewCell {

    @IBOutlet var avatarView: UIImageView!
    @IBOutlet var messageTextView: UILabel!
    @IBOutlet var messageFrameView: UIView!
    @IBOutlet var timestampView: UILabel!
 
    private static let todaysFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.dateStyle = .NoStyle;
        f.timeStyle = .ShortStyle;
        return f;
    })();
    private static let defaultFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.dateFormat = NSDateFormatter.dateFormatFromTemplate("dd.MM, jj:mm", options: 0, locale: NSLocale.currentLocale());
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    private static let fullFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.dateFormat = NSDateFormatter.dateFormatFromTemplate("dd.MM.yyyy, jj:mm", options: 0, locale: NSLocale.currentLocale());
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    
    private func formatTimestamp(ts:NSDate) -> String {
        let flags:NSCalendarUnit = [.Day, .Year];
        let components = NSCalendar.currentCalendar().components(flags, fromDate: ts, toDate: NSDate(), options: []);
        if (components.day < 1) {
            return ChatTableViewCell.todaysFormatter.stringFromDate(ts);
        }
        if (components.year != 0) {
            return ChatTableViewCell.fullFormatter.stringFromDate(ts);
        } else {
            return ChatTableViewCell.defaultFormatter.stringFromDate(ts);
        }
        
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        if messageFrameView != nil {
            //messageFrameView.backgroundColor = UIColor.li();
            messageFrameView.layer.masksToBounds = true;
            messageFrameView.layer.cornerRadius = 6;
        }
        if avatarView != nil {
            avatarView.layer.masksToBounds = true;
            avatarView.layer.cornerRadius = avatarView.frame.height / 2;
        }
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func setTimestamp(ts:NSDate) {
        timestampView.text = formatTimestamp(ts);
    }

}
