//
// CLLocationCoordinate2D.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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
import CoreLocation

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

