//
// RoundButton.swift
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

class RoundButton: UIButton {
    
    override func draw(_ rect: CGRect) {
        let offset = max(rect.width, rect.height) / 2;
        let tmp = CGRect(x: offset, y: offset, width: rect.width - (2 * offset), height: rect.height - (2 * offset));
        super.draw(tmp);
    }
    
    override func layoutSubviews() {
        super.layoutSubviews();
        layer.masksToBounds = true;
        layer.cornerRadius = self.frame.height / 2;
    }
}

class RoundedButton: UIButton {
        
    override func draw(_ rect: CGRect) {
        let offset = rect.height / 2;
        let tmp = CGRect(x: offset, y: offset, width: rect.width - (2 * offset), height: rect.height - (2 * offset));
        super.draw(tmp);
    }
    
    override func layoutSubviews() {
        super.layoutSubviews();
        layer.masksToBounds = true;
        layer.cornerRadius = min(self.frame.height, self.frame.width) / 2;
    }
}

class BadgeButton: RoundedButton {
    
    var widthConstratint: NSLayoutConstraint?;
    
    var title: String? {
        didSet {
            self.setTitle(title, for: .normal);
            self.isHidden = title?.isEmpty ?? true;
            if (isHidden) {
                NSLayoutConstraint.activate([widthConstratint!])
            } else {
                NSLayoutConstraint.deactivate([widthConstratint!]);
            }
            self.layoutSubviews();
            self.setNeedsDisplay();
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup();
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
    
    private func setup() {
        widthConstratint = self.widthAnchor.constraint(equalToConstant: 0);
        NSLayoutConstraint.activate([widthConstratint!]);
        isHidden = true;
    }
    
}
