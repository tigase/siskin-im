//
// BookmarkViewCell.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import UIKit
import Martin
import Combine

public class BookmarkViewCell: UITableViewCell {
 
    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var nameLabel: UILabel!;
    @IBOutlet var jidLabel: UILabel!;
    
    private var avatar: Avatar? {
        didSet {
            avatar?.avatarPublisher.map({ $0 ?? AvatarManager.instance.defaultGroupchatAvatar }).receive(on: DispatchQueue.main).assign(to: \.avatar, on: avatarView).store(in: &cancellables);
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    var bookmark: BookmarkItem? {
        didSet {
            cancellables.removeAll();
            if let bookmark = self.bookmark {
                avatar = AvatarManager.instance.avatarPublisher(for: .init(account: bookmark.account, jid: bookmark.jid.bareJid, mucNickname: nil));
                nameLabel.text = bookmark.name;
                jidLabel.text = bookmark.jid.stringValue;
            } else {
                avatar = nil;
            }
        }
    }
    
}
