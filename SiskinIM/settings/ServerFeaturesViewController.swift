//
// ServerFeaturesViewController.swift
//
// Siskin IM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
import Martin
import Combine

class ServerFeaturesViewController: UITableViewController {

    var client: XMPPClient!;

    private var features: [Feature] = [];

    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        let allFeatures = loadFeatures();
        client.module(.disco).$serverDiscoResult.receive(on: DispatchQueue.main).map({ it -> [Feature] in
            return allFeatures.filter({ $0.matches(it.features) });
        }).sink(receiveValue: { [weak self] features in
            self?.features = features;
            self?.tableView.reloadData();
        }).store(in: &cancellables);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return features.count;
    }
 
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StreamFeatureCell", for: indexPath);
        
        let feature = features[indexPath.row];
        cell.textLabel?.text = feature.xep + ": " + feature.name;
        cell.detailTextLabel?.text = feature.description;
        
        return cell;
    }
    
    fileprivate func loadFeatures() -> [Feature] {
        guard let path = Bundle.main.path(forResource: "server_features_list", ofType: "xml") else {
            return [];
        }
        
        guard let str = try? String(contentsOfFile: path) else {
            return [];
        }
        
        guard let parent = Element.from(string: str) else {
            return [];
        }
        
        return parent.mapChildren(transform: Feature.init(from:));
    }
    
    class Feature {
        let id: String?;
        let xep: String;
        let name: String;
        let description: String?;
        
        convenience init?(from el: Element) {
            guard let xep = el.findChild(name: "xep")?.value, let name = el.findChild(name: "name")?.value else {
                return nil;
            }
            self.init(id: el.getAttribute("id"), xep: xep, name: name, description: el.findChild(name: "description")?.value);
        }
        
        init(id: String?, xep: String, name: String, description: String?) {
            self.id = id;
            self.xep = xep;
            self.name = name;
            self.description = description;
        }
        
        func matches(_ features: [String]) -> Bool {
            guard let id = self.id else {
                return false;
            }
            if id.last == "*" {
                let prefix = id.prefix(upTo: id.index(before: (id.endIndex)));
                return features.contains(where: { (feature) -> Bool in
                    return feature.starts(with: prefix);
                })
            }
            return features.contains(id);
        }
    }
}
