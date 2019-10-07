//
// DiscoEventHandler.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

class DiscoEventHandler: XmppServiceEventHandler {
    
    public static let ACCOUNT_FEATURES_RECEIVED = Notification.Name("accountFeaturesReceived");
    public static let SERVER_FEATURES_RECEIVED = Notification.Name("serverFeaturesReceived");
    
    let events: [Event] = [DiscoveryModule.AccountFeaturesReceivedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as DiscoveryModule.AccountFeaturesReceivedEvent:
            NotificationCenter.default.post(name: DiscoEventHandler.ACCOUNT_FEATURES_RECEIVED, object: e);
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            NotificationCenter.default.post(name: DiscoEventHandler.SERVER_FEATURES_RECEIVED, object: e);
        default:
            break;
        }
    }
}
