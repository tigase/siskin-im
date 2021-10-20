//
// LocationChatTableViewCell.swift
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
import CoreLocation

class LocationChatTableViewCell: BaseChatTableViewCell {
    
    @IBOutlet var mapView: MKMapView! {
        didSet {
            let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)));
            gestureRecognizer.numberOfTapsRequired = 2;
            mapView.addGestureRecognizer(gestureRecognizer);
        }
    }
    
    private let annotation = MKPointAnnotation();
    
    func set(item: ConversationEntry, location: CLLocationCoordinate2D) {
        super.set(item: item);
        mapView.layer.cornerRadius = 5;
        mapView.removeAnnotation(annotation);
        annotation.coordinate = location;
        mapView.addAnnotation(annotation);
        mapView.setRegion(MKCoordinateRegion(center: location, latitudinalMeters: 2000, longitudinalMeters: 2000), animated: true);
    }
    
    @objc func mapTapped(_ sender: Any) {
        let placemark = MKPlacemark(coordinate: annotation.coordinate);
        let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000);
        let item = MKMapItem(placemark: placemark);
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: region.center),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: region.span)
        ])
    }
    
}
