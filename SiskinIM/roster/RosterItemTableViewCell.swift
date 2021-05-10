//
// RosterItemTableViewCell.swift
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

class RosterItemTableViewCell: UITableViewCell {

    override var backgroundColor: UIColor? {
        get {
            return super.backgroundColor;
        }
        set {
            super.backgroundColor = newValue;
            avatarStatusView?.backgroundColor = newValue;
        }
    }
    
    @IBOutlet var avatarStatusView: AvatarStatusView! {
        didSet {
            self.avatarStatusView?.backgroundColor = self.backgroundColor;
        }
    }
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var statusLabel: UILabel!
    
    private var originalBackgroundColor: UIColor?;
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
//    override var isHighlighted: Bool {
//        didSet {
//            avatarStatusView?.backgroundColor = isHighlighted ? UIColor(named: "tintColor") :  self.backgroundColor;
//        }
//    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        if originalBackgroundColor == nil {
            originalBackgroundColor = self.backgroundColor;
            if originalBackgroundColor == nil {
                self.backgroundColor = UIColor.systemBackground;
            }
        }
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = selected ? UIColor.lightGray : self.originalBackgroundColor;
            }
        } else {
            self.backgroundColor = selected ? UIColor.lightGray : originalBackgroundColor;
        }
    }
}
