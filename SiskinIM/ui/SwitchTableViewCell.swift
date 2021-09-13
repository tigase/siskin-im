//
// SwitchTableViewCell.swift
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
import Combine

class SwitchTableViewCell: UITableViewCell {

    @IBOutlet var switchView: UISwitch!
    
    var valueChangedListener: ((UISwitch) -> Void)?;
    
    private var cancellables: Set<AnyCancellable> = [];
    private let subject = PassthroughSubject<Bool, Never>();
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    @IBAction func valueChanged(_ sender: UISwitch) {
        valueChangedListener?(sender);
        subject.send(sender.isOn);
    }
    
    func reset() {
        cancellables.removeAll();
    }
    
    func assign(from publisher: AnyPublisher<Bool,Never>) {
        publisher.removeDuplicates().assign(to: \.isOn, on: switchView).store(in: &cancellables);
    }

    func sink<Root>(to keyPath: ReferenceWritableKeyPath<Root, Bool>, on object: Root) {
        subject.removeDuplicates().assign(to: keyPath, on: object).store(in: &cancellables);
    }

    func sink<Root,T>(map: @escaping (Bool)->T, to keyPath: ReferenceWritableKeyPath<Root, T>, on object: Root) {
        subject.removeDuplicates().map(map).assign(to: keyPath, on: object).store(in: &cancellables);
    }
    
    func bind(_ fn: (SwitchTableViewCell)->Void) {
        reset();
        fn(self);
    }
}
