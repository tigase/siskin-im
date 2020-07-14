//
// ChatTableViewCell.swift
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
import TigaseSwift

class ChatTableViewCell: BaseChatTableViewCell {

    @IBOutlet var messageTextView: MessageTextView!
        
    fileprivate var messageLinkTapGestureRecognizer: UITapGestureRecognizer!;
    
    fileprivate var originalTextColor: UIColor!;
    fileprivate var links: [Link] = [];
    
    override var backgroundColor: UIColor? {
        didSet {
            self.messageTextView.backgroundColor = self.backgroundColor;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        originalTextColor = messageTextView.textColor;
        messageLinkTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(messageLinkTapGestureDidFire));
        messageLinkTapGestureRecognizer.numberOfTapsRequired = 1;
        messageLinkTapGestureRecognizer.cancelsTouchesInView = false;
        messageTextView.addGestureRecognizer(messageLinkTapGestureRecognizer);
    }
    
    func set(message item: ChatMessage) {
        super.set(item: item);
                
        self.links.removeAll();
            
        let attrText = NSMutableAttributedString(string: item.message);
            
        if let detect = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue | NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detect.matches(in: item.message, options: .reportCompletion, range: NSMakeRange(0, item.message.count));
            for match in matches {
                var url: URL? = nil;
                if match.url != nil {
                    url = match.url;
                }
                if match.phoneNumber != nil {
                    url = URL(string: "tel:\(match.phoneNumber!.replacingOccurrences(of: " ", with: "-"))");
                }
                if match.addressComponents != nil {
                    if let query = match.addressComponents!.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                        url = URL(string: "http://maps.apple.com/?q=\(query)");
                    }
                }
                if match.date != nil {
                    url = URL(string: "calshow:\(match.date!.timeIntervalSinceReferenceDate)");
                }
                if url != nil {
                    self.links.append(Link(url: url!, range: match.range));
                    
                    attrText.setAttributes([NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue, NSAttributedString.Key.foregroundColor: self.linkColor()], range: match.range);
                }
            }
        }
        if Settings.EnableMarkdownFormatting.getBool() {
            Markdown.applyStyling(attributedString: attrText, font: UIFont.systemFont(ofSize: self.messageTextView.fontSize), showEmoticons:Settings.ShowEmoticons.getBool());
        }
        self.messageTextView.attributedText = attrText;
        if item.state.isError {
            if (self.messageTextView.text?.isEmpty ?? true), let error = item.error {
                self.messageTextView.text = "Error: \(error)";
            }
            if item.state.direction == .incoming {
                self.messageTextView.textColor = UIColor.red;
            }
        } else {
            if item.encryption == .notForThisDevice || item.encryption == .decryptionFailed {
                self.messageTextView.textColor = self.originalTextColor;
            }
        }
    }
    
    func linkColor() -> UIColor {
        if #available(iOS 13.0, *) {
            return UIColor.systemBlue;
        } else {
            return UIColor.blue;
        }
    }
        
    @objc func messageLinkTapGestureDidFire(_ recognizer: UITapGestureRecognizer) {
        guard self.messageTextView.attributedText != nil else {
            return;
        }
        
//        let point = recognizer.location(in: self.messageTextView);
//        let layoutManager = NSLayoutManager();
//        let attrText = self.messageTextView.attributedText!.mutableCopy() as! NSMutableAttributedString;
//        attrText.addAttribute(NSAttributedString.Key.font, value: self.messageTextView.font!, range: NSRange(location: 0, length: attrText.length));
//        let textStorage = NSTextStorage(attributedString: attrText);
//        let textContainer = NSTextContainer(size: self.messageTextView.bounds.size);
////        textContainer.maximumNumberOfLines = self.messageTextView.numberOfLines;
//        layoutManager.usesFontLeading = true;
//        textContainer.lineFragmentPadding = 0;
////        textContainer.lineBreakMode = self.messageTextView.lineBreakMode;
//        layoutManager.addTextContainer(textContainer);
//        textStorage.addLayoutManager(layoutManager);
//        
//        let idx = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil);
//        if let url = links.first(where: { link -> Bool in link.contains(idx: idx)}) {
////        if let url = attrText.attribute(NSAttributedString.Key.link, at: idx, effectiveRange: nil) as? NSURL {
//            UIApplication.shared.open(url.url);
//        }
    }
        
    class Link {
        let url: URL;
        let range: NSRange;
        
        init(url: URL, range: NSRange) {
            self.url = url;
            self.range = range;
        }
        
        func contains(idx: Int) -> Bool {
            return range.contains(idx);
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromOptionalNSTextCheckingKeyDictionary(_ input: [NSTextCheckingKey: Any]?) -> [String: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
	return input.rawValue
}
