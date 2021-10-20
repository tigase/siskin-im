//
// ShareLocationSearchResultsController.swift
//
// Siskin IM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import MapKit

class ShareLocationSearchResultsController: UITableViewController, UISearchResultsUpdating {
    
    var mapView: MKMapView!;
    weak var mapController: ShareLocationController!;
    
    private var matchingItems: [MKMapItem] = [];
    private var id = UUID();
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text else {
            return;
        }
        
        let id = UUID();
        self.id = id;
        
        let request = MKLocalSearch.Request();
        request.naturalLanguageQuery = query;
        request.region = mapView.region;
        
        let search = MKLocalSearch(request: request);
        search.start(completionHandler: { (response, _) in
            guard let response = response, self.id == id else {
                return;
            }
            self.matchingItems = response.mapItems;
            self.tableView.reloadData();
        })
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return matchingItems.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil);
        let item = matchingItems[indexPath.row].placemark;
        cell.textLabel?.text = item.name;
        let address = [item.thoroughfare, item.locality, item.subLocality, item.administrativeArea, item.postalCode, item.country];
        cell.detailTextLabel?.text = address.compactMap({ $0 }).joined(separator: ", ");
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = matchingItems[indexPath.row].placemark;
        mapController.setCurrentLocation(placemark: item, coordinate: item.coordinate, zoomIn: true);
        self.dismiss(animated: true, completion: nil);
    }
}
