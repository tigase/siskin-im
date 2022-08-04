//
// HttpFileUploadModule.swift
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
import Combine
import Martin

// Dummy implementation - it would be better to replace it with some better feature discovery than on each reconnection
class HttpFileUploadModule: Martin.HttpFileUploadModule {
    
    @Published
    var isAvailable: Bool = true;
    
    var isAvailablePublisher: AnyPublisher<Bool,Never> {
        return $isAvailable.eraseToAnyPublisher();
    }
    
}
