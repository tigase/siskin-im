//
// XMPPClient_extension.swift
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
import Martin

extension XMPPClient {
    
    fileprivate static let RETRY_NO_KEY = "retryNo";
    
    var retryNo: Int {
        get {
            return sessionObject.getProperty(XMPPClient.RETRY_NO_KEY) ?? 0;
        }
        set {
            sessionObject.setUserProperty(XMPPClient.RETRY_NO_KEY, value: newValue);
        }
    }
    
}

extension SocketConnectorNetwork.Endpoint: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        self.init(proto: ConnectorProtocol(rawValue: try container.decode(String.self, forKey: .proto))!, host: try container.decode(String.self, forKey: .host), port: try container.decode(Int.self, forKey: .port));
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(proto.rawValue, forKey: .proto);
        try container.encode(host, forKey: .host);
        try container.encode(port, forKey: .port);
    }
    
    public enum CodingKeys: String, CodingKey {
        case proto
        case host
        case port
    }
}
