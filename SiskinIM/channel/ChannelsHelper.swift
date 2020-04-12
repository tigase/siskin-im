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
import TigaseSwift

class ChannelsHelper {
    
    static func findChannels(for account: BareJID, at components: [Component], completionHandler: @escaping ([DiscoveryModule.Item])->Void) {
        guard let client = XmppService.instance.getClient(for: account), let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            completionHandler([]);
            return;
        }
        var allItems: [DiscoveryModule.Item] = [];
        let group = DispatchGroup();
        for component in components {
            group.enter();
            discoModule.getItems(for: component.jid, completionHandler: { result in
                 switch result {
                 case .success(_, let items):
                     DispatchQueue.main.async {
                        allItems.append(contentsOf: items);
                     }
                 case .failure(_, _):
                     break;
                 }
                 group.leave();
             });
        }
        group.notify(queue: DispatchQueue.main, execute: {
            completionHandler(allItems);
        })
    }
    
    static func findComponents(for account: BareJID, at domain: String, completionHandler: @escaping ([Component])->Void) {
        let domainJid = JID(domain);
        guard let client = XmppService.instance.getClient(for: account), let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            completionHandler([]);
            return;
        }
        
        var components: [Component] = [];
        let group = DispatchGroup();
        group.enter();
        retrieveComponent(from: domainJid, name: nil, discoModule: discoModule, completionHandler: { result in
            switch result {
            case .success(let component):
                DispatchQueue.main.async {
                    components.append(component);
                }
                group.leave();
            case .failure(_):
                discoModule.getItems(for: domainJid, completionHandler: { result in
                    switch result {
                    case .success(_, let items):
                        // we need to do disco on all components to find out local mix/muc component..
                        // maybe this should be done once for all "views"?
                        for item in items {
                            group.enter();
                            self.retrieveComponent(from: item.jid, name: item.name, discoModule: discoModule, completionHandler: { result in
                                switch result {
                                case .success(let component):
                                    DispatchQueue.main.async {
                                        components.append(component);
                                    }
                                case .failure(_):
                                    break;
                                }
                                group.leave();
                            });
                        }
                    case .failure(_, _):
                        break;
                    }
                    group.leave();
                });
            }
        })
        
        group.notify(queue: DispatchQueue.main, execute: {
            completionHandler(components);
        })
    }
    
    static func retrieveComponent(from jid: JID, name: String?, discoModule: DiscoveryModule, completionHandler: @escaping (Result<Component,ErrorCondition>)->Void) {
        discoModule.getInfo(for: jid, completionHandler: { result in
            switch result {
            case .success(_, let identities, let features):
                guard let component = Component(jid: jid, name: name, identities: identities, features: features) else {
                    completionHandler(.failure(.item_not_found));
                    return;
                }
                completionHandler(.success(component));
            case .failure(let errorCondition, _):
                completionHandler(.failure(errorCondition));
            }
        })

    }
    
    enum ComponentType {
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
    
    class Component {
        let jid: JID;
        let name: String?;
        let type: ComponentType;
        
        convenience init?(jid: JID, name: String?, identities: [DiscoveryModule.Identity], features: [String]) {
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
