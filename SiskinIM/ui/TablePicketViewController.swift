//
// TablePicketView.swift
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

class TablePickerViewController: UITableViewController {

    var selected: Int = 0;
    var items = [TablePickerViewItemsProtocol]();
    var onSelectionChange: ((TablePickerViewItemsProtocol)->Void)?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "item");
        tableView.dataSource = self;
        tableView.delegate = self;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath);
        cell.textLabel!.text = items[indexPath.row].description;
        cell.accessoryType = indexPath.row == selected ? .checkmark : .none;
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false);
        if selected != indexPath.row {
            selected = indexPath.row;
            tableView.reloadData();
            onSelectionChange?(items[selected]);
        }
    }
    
}

protocol TablePickerViewItemsProtocol {
    
    var description: String { get };
    
}
