//
// CurrentDatePublisher.swift
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
import Combine

@preconcurrency
struct CurrentTimePublisher {

    public static var publisher: CurrentValueSubject<Date,Never> {
        return instance.publisher;
    }

    private static let instance = CurrentTimePublisher();
    
    private let cancellable: Cancellable;
    private let publisher: CurrentValueSubject<Date,Never>;
    
    init() {
        publisher = CurrentValueSubject<Date,Never>(Date());
        cancellable = Timer.publish(every: 30, on: .main, in: .default).autoconnect().assign(to: \.value, on: publisher);
    }
}
