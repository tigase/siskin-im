//
// DisplayableIdProtocol.swift
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
//

import Foundation
import Martin
import UIKit
import Combine

public protocol DisplayableIdProtocol {
    
    var displayName: String { get }
    var displayNamePublisher: Published<String>.Publisher { get }

    var status: Presence.Show? { get }
    var statusPublisher: Published<Presence.Show?>.Publisher { get }
    
    var avatar: Avatar { get }
    
    var description: String? { get }
    var descriptionPublisher: Published<String?>.Publisher { get }
}

public protocol DisplayableIdWithKeyProtocol: DisplayableIdProtocol {
    
    var account: BareJID { get }
    var jid: BareJID { get }
    
}
