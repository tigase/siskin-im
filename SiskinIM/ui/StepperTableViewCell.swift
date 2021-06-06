//
// StepperTableViewCell.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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
import Combine

class StepperTableViewCell: UITableViewCell {
    
    @IBOutlet var labelView: UILabel!
    @IBOutlet var stepperView: UIStepper!
    
    var valueChangedListener: ((UIStepper) -> Void)?;
    var updateLabel: ((Double)->String?)?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
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

    func reset() {
        cancellables.removeAll();
    }
    
    func assign(from publisher: AnyPublisher<Double,Never>, labelGenerator: ((Double)->String)? = nil) {
        publisher.removeDuplicates().assign(to: \.value, on: stepperView).store(in: &cancellables);
        if labelGenerator != nil {
            publisher.map(labelGenerator!).assign(to: \.text, on: labelView).store(in: &cancellables);
        }
    }

    func assign(from publisher: AnyPublisher<Int,Never>, labelGenerator: ((Int)->String)? = nil) {
        publisher.map({ Double($0) }).removeDuplicates().assign(to: \.value, on: stepperView).store(in: &cancellables);
        if labelGenerator != nil {
            publisher.map(labelGenerator!).assign(to: \.text, on: labelView).store(in: &cancellables);
        }
    }

    func sink<Root>(to keyPath: ReferenceWritableKeyPath<Root, Double>, on object: Root) {
        stepperView.publisher(for: \.value).removeDuplicates().assign(to: keyPath, on: object).store(in: &cancellables);
    }

    func sink<Root>(to keyPath: ReferenceWritableKeyPath<Root, Int>, on object: Root) {
        stepperView.publisher(for: \.value).map({ Int($0) }).removeDuplicates().assign(to: keyPath, on: object).store(in: &cancellables);
    }
    
    func bind(_ fn: (StepperTableViewCell)->Void) {
        reset();
        fn(self);
    }

}
