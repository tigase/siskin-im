//
// ChannelsHelper.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

class ChannelsHelper {
    
    static func findChannels(for client: XMPPClient, at components: [Component]) async -> [DiscoveryModule.Item] {
        return await withTaskGroup(of: [DiscoveryModule.Item]?.self, body: { group in
            for component in components {
                group.addTask(operation: {
                    try? await client.module(.disco).items(for: component.jid).items
                })
            }
            return await group.reduce(into: [DiscoveryModule.Item](), { $0.append(contentsOf: $1 ?? [])})
        })
    }
    
    static func findComponents(for client: XMPPClient, at domain: String) async throws -> [Component] {
        let domainJid = JID(domain);
        let discoModule = client.module(.disco);
        do {
            return [try await retrieveComponent(from: domainJid, name: nil, discoModule: discoModule)];
        } catch {
            let items = try await discoModule.items(for: domainJid);
            return await withTaskGroup(of: Component?.self, body: { group in
                for item in items.items {
                    group.addTask(operation: {
                        try? await retrieveComponent(from: item.jid, name: item.name, discoModule: discoModule);
                    })
                }
                return await group.reduce(into: [Component](), { if let component = $1 { $0.append(component) } });
            })
        }
    }
    
    static func queryChannel(for client: XMPPClient, at components: [Component], name: String) async -> [DiscoveryModule.Item] {
        let discoModule = client.module(.disco);
        return await withTaskGroup(of: DiscoveryModule.Item?.self, body: { group in
            for component in components {
                group.addTask(operation: {
                    let channelJid = JID(BareJID(localPart: name, domain: component.jid.domain));
                    if let info = try? await discoModule.info(for: channelJid, node: nil) {
                        return DiscoveryModule.Item(jid: channelJid, name: info.identities.first?.name)
                    } else {
                        return nil;
                    }
                })
            }
            return await group.reduce(into: [DiscoveryModule.Item](), { if let item = $1 { $0.append(item) } })
        })
    }
    
    static func retrieveComponent(from jid: JID, name: String?, discoModule: DiscoveryModule) async throws -> Component {
        let info = try await discoModule.info(for: jid);
        guard let component = Component(jid: jid, name: name, identities: info.identities, features: info.features) else {
            throw XMPPError(condition: .item_not_found);
        }
        return component;
    }
    
    enum ComponentType: Sendable {
        case muc
        case mix
        
        static func from(identities: [DiscoveryModule.Identity], features: [String]) -> ComponentType? {
            if identities.first(where: { $0.category == "conference" && $0.type == "mix" }) != nil && features.contains(MixModule.CORE_XMLNS) {
                return .mix;
            }
            if identities.first(where: { $0.category == "conference" }) != nil && features.contains("http://jabber.org/protocol/muc") {
                return .muc;
            }
            return nil;
        }
    }
    
    struct Component: Sendable {
        let jid: JID;
        let name: String?;
        let type: ComponentType;
        
        init?(jid: JID, name: String?, identities: [DiscoveryModule.Identity], features: [String]) {
            guard let type = ComponentType.from(identities: identities, features: features) else {
                return nil;
            }
            self.init(jid: jid, name: name ?? identities.first(where: { $0.name != nil})?.name, type: type);
        }
        
        init(jid: JID, name: String?, type: ComponentType) {
            self.jid = jid;
            self.name = name;
            self.type = type;
        }
    }
}
