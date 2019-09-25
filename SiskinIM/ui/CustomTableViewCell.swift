//
// CustomTableViewCell.swift
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

class CustomTableViewCell: UITableViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib();
        let tmp = UIView();
        tmp.backgroundColor = Appearance.current.systemBackground;
        selectedBackgroundView = tmp;
    }
 
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = highlighted ? Appearance.current.systemBackground.mix(color: Appearance.current.tableViewCellHighlightColor, ratio: nil) : Appearance.current.systemBackground;
                //self.backgroundColor = highlighted ? Appearance.current.tableViewCellHighlightColor() : Appearance.current.tableViewCellBackgroundColor();
            }
        } else {
            self.backgroundColor = highlighted ? Appearance.current.systemBackground.mix(color: Appearance.current.tableViewCellHighlightColor, ratio: nil) : Appearance.current.systemBackground;
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = selected ? Appearance.current.systemBackground.mix(color: Appearance.current.tableViewCellHighlightColor, ratio: nil) : Appearance.current.systemBackground;
            }
        } else {
            self.backgroundColor = selected ? Appearance.current.systemBackground.mix(color: Appearance.current.tableViewCellHighlightColor, ratio: nil) : Appearance.current.systemBackground;
        }
    }

}
