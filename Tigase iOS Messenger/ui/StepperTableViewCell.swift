//
// StepperTableViewCell.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

class StepperTableViewCell: CustomTableViewCell {
    
    @IBOutlet var labelView: UILabel!
    @IBOutlet var stepperView: UIStepper!
    
    var valueChangedListener: ((UIStepper) -> Void)?;
    var updateLabel: ((Double)->String?)?;
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Configure the view for the selected state
    }
    
    @IBAction func valueChanged(_ sender: UIStepper) {
        valueChangedListener?(sender);
        setValue(stepperView.value);
    }
    
    func setValue(_ value: Double) {
        stepperView.value = value;
        if updateLabel != nil {
            labelView.text = updateLabel!(value);
        }
    }
}
