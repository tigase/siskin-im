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
    
}

class ChatTableViewMeCell: UITableViewCell {
    

    @IBOutlet var messageView: MessageTextView!
    
    func set(item: ConversationEntry, message msg: String) {
        let nickname = item.sender.nickname ?? "SOMEONE:";
        let preferredFont = UIFont.preferredFont(forTextStyle: .subheadline);
        let message = NSMutableAttributedString(string: "\(nickname) ", attributes: [.font: UIFont(descriptor: preferredFont.fontDescriptor.withSymbolicTraits([.traitBold,.traitItalic])!, size: 0), .foregroundColor: UIColor.secondaryLabel]);
        message.append(NSAttributedString(string: "\(msg.dropFirst(4))", attributes: [.font: UIFont(descriptor: preferredFont.fontDescriptor.withSymbolicTraits(.traitItalic)!, size: 0), .foregroundColor: UIColor.secondaryLabel]));
        self.messageView.attributedText = message;
    }

}
