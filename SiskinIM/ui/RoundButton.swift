//
//  RoundButton.swift
//  Tigase-iOS-Messenger
//
//  Created by Andrzej Wójcik on 06/01/2019.
//  Copyright © 2019 Tigase, Inc. All rights reserved.
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
