//
// ChatTableViewSystemCell.swift
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

class ChatTableViewSystemCell: UITableViewCell {
    

    @IBOutlet var messageView: UILabel!
    
    func set(item: SystemMessage) {
        switch item.kind {
        case .unreadMessages:
            messageView.text = "Unread messages"
        }
    }
}

class ChatTableViewMeCell: UITableViewCell {
    

    @IBOutlet var messageView: MessageTextView!
    
    func textColor() -> UIColor {
        if #available(iOS 13.0, *) {
            return .secondaryLabel;
        }
        return UIColor(red: 0.23529411764705882, green: 0.23529411764705882, blue: 0.2627450980392157, alpha: 0.6);
    }
    
    func set(item: ChatMessage, nickname: String?) {
        var fontDescriptor = UIFont.systemFont(ofSize: self.messageView.fontSize, weight: .medium).fontDescriptor.withSymbolicTraits([.traitItalic]) ?? UIFont.systemFont(ofSize: self.messageView.fontSize, weight: .medium).fontDescriptor;
        let message = NSMutableAttributedString(string: "\(nickname ?? item.jid.stringValue) ", attributes: [.font: UIFont(descriptor: fontDescriptor, size: 0), .foregroundColor: textColor()]);
        fontDescriptor = UIFont.systemFont(ofSize: self.messageView.fontSize, weight: .regular).fontDescriptor.withSymbolicTraits([.traitItalic]) ?? UIFont.systemFont(ofSize: self.messageView.fontSize, weight: .medium).fontDescriptor;
        message.append(NSAttributedString(string: "\(item.message.dropFirst(4))", attributes: [.font: UIFont(descriptor: fontDescriptor, size: 0), .foregroundColor: textColor()]));
        self.messageView.attributedText = message;
    }

}
