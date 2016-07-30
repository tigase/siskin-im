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

    @IBOutlet var avatarView: UIImageView?
    @IBOutlet var messageTextView: UILabel!
    @IBOutlet var messageFrameView: UIView!
    @IBOutlet var timestampView: UILabel!
    
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!;
    
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
            avatarView!.layer.masksToBounds = true;
            avatarView!.layer.cornerRadius = avatarView!.frame.height / 2;
        }
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressDidFire));
//        longPressGestureRecognizer.delegate = self;
        messageTextView.addGestureRecognizer(longPressGestureRecognizer);
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func setTimestamp(ts:NSDate) {
        timestampView.text = formatTimestamp(ts);
    }

    func setMessageText(text: String?) {
        if text != nil && (text!.containsString("http:") || text!.containsString("https://")) {
            let attrText = NSMutableAttributedString(string: text!);
            
            if let detect = try? NSDataDetector(types: NSTextCheckingType.Link.rawValue | NSTextCheckingType.PhoneNumber.rawValue | NSTextCheckingType.Address.rawValue) {
                let matches = detect.matchesInString(text!, options: .ReportCompletion, range: NSMakeRange(0, text!.characters.count));
                for match in matches {
                    if match.URL != nil {
                        attrText.addAttribute(NSLinkAttributeName, value: match.URL!, range: match.range);
                    }
                    if match.phoneNumber != nil {
                        attrText.addAttribute(NSLinkAttributeName, value: NSURL(string: "tel:\(match.phoneNumber!)")!, range: match.range);
                    }
                    if match.addressComponents != nil {
                        let query = match.addressComponents?.values.joinWithSeparator(",").stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet());
                        attrText.addAttribute(NSLinkAttributeName, value: NSURL(string: "http://maps.apple.com/?q=\(query)")!, range: match.range);
                    }
                }
            }
            self.messageTextView.attributedText = attrText;
        } else {
            self.messageTextView.text = text;
        }
    }
    
    func longPressDidFire(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .Began:
            guard self.messageTextView.attributedText != nil else {
                return;
            }
            
            let point = recognizer.locationInView(self.messageTextView);
            let layoutManager = NSLayoutManager();
            let textStorage = NSTextStorage(attributedString: self.messageTextView.attributedText!);
            textStorage.addLayoutManager(layoutManager);
            let textContainer = NSTextContainer(size: self.messageTextView.bounds.size);
            textContainer.lineFragmentPadding = 0;
            textContainer.lineBreakMode = self.messageTextView.lineBreakMode;
            layoutManager.addTextContainer(textContainer);
            let idx = layoutManager.characterIndexForPoint(point, inTextContainer: textContainer, fractionOfDistanceBetweenInsertionPoints: nil);
            if let url = self.messageTextView.attributedText?.attribute(NSLinkAttributeName, atIndex: idx, effectiveRange: nil) as? NSURL {
                UIApplication.sharedApplication().openURL(url);
            }
        default:
            break;
        }
    }
}
