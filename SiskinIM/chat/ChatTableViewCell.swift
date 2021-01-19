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

class ChatTableViewCell: BaseChatTableViewCell, UITextViewDelegate {

    @IBOutlet var messageTextView: MessageTextView!
        
    fileprivate var originalTextColor: UIColor!;
    
    override var backgroundColor: UIColor? {
        didSet {
            self.messageTextView.backgroundColor = self.backgroundColor;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        originalTextColor = messageTextView.textColor;
    }
    
    func set(message item: ChatMessage) {
        messageTextView.textView.delegate = self;
        super.set(item: item);
                            
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
                if let url = url {
                    attrText.setAttributes([.link : url], range: match.range);
                }
            }
        }
        attrText.addAttribute(.foregroundColor, value: UIColor(named: "chatMessageText") as Any, range: NSRange(location: 0, length: attrText.length));
        if Settings.EnableMarkdownFormatting.getBool() {
            Markdown.applyStyling(attributedString: attrText, font: UIFont.systemFont(ofSize: self.messageTextView.fontSize), showEmoticons:Settings.ShowEmoticons.getBool());
        } else {
            attrText.addAttribute(.font, value: UIFont.systemFont(ofSize: self.messageTextView.fontSize), range: NSRange(location: 0, length: attrText.length));
            attrText.fixAttributes(in: NSRange(location: 0, length: attrText.length));

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
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL);
        return false;
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
