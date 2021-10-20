//
// ShareLocationController.swift
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
import CoreLocationUI
import CoreLocation

class ShareLocationController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {
    
    private let searchResultsController = ShareLocationSearchResultsController();
    private let mapView = MKMapView();
    private let locationManager = CLLocationManager();
    
    private let currentAnnotation = MKPointAnnotation();
    
    var conversation: Conversation!;
    
    private var activityIndicator: UIActivityIndicatorView?;
    
    override func viewDidLoad() {
        self.title = NSLocalizedString("Select location", comment: "location selection window title");
        self.view = mapView;
        super.viewDidLoad();
        mapView.delegate = self;
        let navAppearance = UINavigationBarAppearance();
        navAppearance.configureWithDefaultBackground();
        navAppearance.backgroundEffect = UIBlurEffect(style: .regular);
        self.navigationController?.navigationBar.standardAppearance = navAppearance;
        self.navigationController?.navigationBar.scrollEdgeAppearance = navAppearance;
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissView))
        self.navigationItem.searchController = UISearchController(searchResultsController: searchResultsController);
        self.navigationItem.searchController?.hidesNavigationBarDuringPresentation = false;
        self.navigationItem.searchController?.searchBar.placeholder = NSLocalizedString("Search for places", comment: "placeholder for location selection search bar");
        self.navigationItem.searchController?.searchResultsUpdater = searchResultsController;
        self.definesPresentationContext = true;
        self.searchResultsController.mapView = mapView;
        self.searchResultsController.mapController = self;
        
        if #available(iOS 15, *) {
            let locationButton = CLLocationButton(frame: .init(origin: .zero, size: CGSize(width: 100, height: 100)));
            locationButton.translatesAutoresizingMaskIntoConstraints = false;
            locationButton.backgroundColor = UIColor(named: "tintColor");
            locationButton.tintColor = .systemBackground;
            locationButton.tintAdjustmentMode = .dimmed;
            locationButton.label = .none;
            locationButton.icon = .arrowFilled;
            locationButton.fontSize = 24;
            locationButton.cornerRadius = 32;
            locationButton.isOpaque = false;
            self.view.addSubview(locationButton)

            locationButton.addTarget(self, action: #selector(requestCurrentLocationiOS15), for: .touchUpInside);

            NSLayoutConstraint.activate([ view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: locationButton.bottomAnchor, constant: 20), view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: locationButton.trailingAnchor, constant: 20) ]);
        } else {
            let locationButton = RoundButton(type: .custom);
            locationButton.translatesAutoresizingMaskIntoConstraints = false;
            locationButton.setImage(UIImage(systemName: "location.fill"), for: .normal);
            locationButton.backgroundColor = UIColor(named: "tintColor");
            locationButton.tintColor = .systemBackground;
            locationButton.isOpaque = true;
            
            self.view.addSubview(locationButton)
            
            locationButton.addTarget(self, action: #selector(requestCurrentLocationPreiOS15(_:)), for: .touchUpInside);
            
            NSLayoutConstraint.activate([ view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: locationButton.bottomAnchor, constant: 20), view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: locationButton.trailingAnchor, constant: 20), locationButton.widthAnchor.constraint(equalTo: locationButton.heightAnchor), locationButton.heightAnchor.constraint(equalToConstant: 40) ]);
        }
        
        let tapGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTap(_:)));
        self.mapView.addGestureRecognizer(tapGesture);
    }
    
    @objc func dismissView() {
        self.navigationController?.dismiss(animated: true, completion: nil);
    }
    
    @objc func handleTap(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .ended else {
            return;
        }
        let coordinate = self.mapView.convert(sender.location(in: self.mapView), toCoordinateFrom: self.mapView);
        setCurrentLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), zoomIn: false);
    }
    
    @available(iOS, obsoleted: 15, message: "We are using CLLocationButton now!")
    @objc func requestCurrentLocationPreiOS15(_ sender: UIButton) {
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            requestCurrentLocation();
        } else {
            locationManager.delegate = self;
            locationManager.requestWhenInUseAuthorization();
        }
    }
    
    @available(iOS 15.0, *)
    @objc func requestCurrentLocationiOS15() {
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            requestCurrentLocation();
        } else {
            locationManager.delegate = self;
        }
    }
    
    private func requestCurrentLocation() {
        if activityIndicator == nil {
            activityIndicator = UIActivityIndicatorView(style: .large);
            activityIndicator?.translatesAutoresizingMaskIntoConstraints = false;
            activityIndicator?.hidesWhenStopped = true;
            mapView.addSubview(activityIndicator!);
            NSLayoutConstraint.activate([mapView.centerXAnchor.constraint(equalTo: activityIndicator!.centerXAnchor), mapView.centerYAnchor.constraint(equalTo: activityIndicator!.centerYAnchor)]);
        }
//        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
        locationManager.delegate = self;
        activityIndicator?.startAnimating();
        locationManager.requestLocation();
    }
    
    @available(iOS, obsoleted: 15, message: "We are using CLLocationButton now!")
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            requestCurrentLocation();
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let view = MKPinAnnotationView(annotation: annotation, reuseIdentifier: nil);
        view.isEnabled = true;
        view.isDraggable = true;
        view.canShowCallout = true;
        let accessory = UIButton(type: .custom);
        accessory.setImage(UIImage(systemName: "location.fill"), for: .normal);
        accessory.tintColor = UIColor(named: "tintColor");
        accessory.frame = CGRect(origin: .zero, size: CGSize(width: 30, height: 30));
        accessory.addTarget(self, action: #selector(shareSelectedLocation), for: .touchUpInside);
        view.rightCalloutAccessoryView = accessory;
        return view;
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        if newState == .ending, let annotation = view.annotation {
            setCurrentLocation(CLLocation(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude), zoomIn: false);
        }
    }
    
    @objc func shareSelectedLocation(_ sender: Any) {
        conversation.sendMessage(text: currentAnnotation.geoUri, correctedMessageOriginId: nil);
        dismissView();
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        activityIndicator?.stopAnimating();
        guard let location = locations.first else {
            return;
        }
        
        setCurrentLocation(location, zoomIn: true);
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        activityIndicator?.stopAnimating();
        if #available(iOS 15.0, *), let err = error as? CLError, err.code == .denied {
            return;
        }
        let alert = UIAlertController(title: NSLocalizedString("Failure", comment: "alert window title"), message: error.localizedDescription, preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "action label"), style: .cancel, handler: nil));
        self.present(alert, animated: true, completion: nil);
    }
    
    func setCurrentLocation(placemark place: CLPlacemark, coordinate: CLLocationCoordinate2D, zoomIn: Bool) {
        self.mapView.removeAnnotation(currentAnnotation);
        currentAnnotation.coordinate = coordinate;
        let address = [place.name, place.thoroughfare, place.locality, place.subLocality, place.administrativeArea, place.postalCode, place.country].compactMap({ $0 });
        if address.isEmpty {
            self.currentAnnotation.title = NSLocalizedString("Your location", comment: "search location pin label");
        } else {
            self.currentAnnotation.title = address.joined(separator: ", ");
        }
        DispatchQueue.main.async {
            self.mapView.addAnnotation(self.currentAnnotation);
            if zoomIn {
                self.mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000), animated: true);
            } else {
                self.mapView.centerCoordinate = coordinate;
            }
            
            self.mapView.selectAnnotation(self.currentAnnotation, animated: true);
        }
    }
    
    private func setCurrentLocation(_ location: CLLocation, zoomIn: Bool) {
        self.mapView.removeAnnotation(currentAnnotation);
        
        
        let geocoder = CLGeocoder();
        geocoder.reverseGeocodeLocation(location, completionHandler: { (places, error) in
            guard error == nil, let place = places?.first else {
                return;
            }
            self.setCurrentLocation(placemark: place, coordinate: location.coordinate, zoomIn: zoomIn);
        })
    }
}

extension MKPointAnnotation {
    
    var geoUri: String {
        return coordinate.geoUri;
    }
    
}

extension CLLocationCoordinate2D {
    
    public static let geoRegex = try! NSRegularExpression(pattern: "geo:\\-?[0-9]+\\.?[0-9]*,\\-?[0-9]+\\.?[0-9]*");
    
    public var geoUri: String {
        return "geo:\(self.latitude),\(self.longitude)";
    }
    
    public init?(geoUri: String) {
        guard geoUri.starts(with: "geo:"), !CLLocationCoordinate2D.geoRegex.matches(in: geoUri, options: [], range: NSRange(location: 0, length: geoUri.count)).isEmpty else {
            return nil;
        }
        let parts = geoUri.dropFirst(4).split(separator: ",").compactMap({ Double(String($0)) });
        guard parts.count == 2 else {
            return nil;
        }
        self.init(latitude: parts[0], longitude: parts[1]);
    }
    
}

extension CLLocationCoordinate2D: Hashable {
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude;
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.latitude);
        hasher.combine(self.longitude);
    }
    
}
