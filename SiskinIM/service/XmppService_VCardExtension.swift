//
// XmppService_VCardExtension.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

import UIKit
import TigaseSwift

extension XmppService {
    
    open func refreshVCard(account: BareJID, for jid: BareJID?, onSuccess: ((VCard)->Void)?, onError:  ((ErrorCondition?)->Void)?) {
        guard let client = getClient(forJid: account) else {
            onError?(ErrorCondition.service_unavailable);
            return;
        }
        
        retrieveVCard(account: account, for: jid == nil ? nil : JID(jid!), completionHandler: { result in
            switch result {
            case .success(let vcard):
                DispatchQueue.global(qos: .default).async() {
                    self.dbVCardsCache.updateVCard(for: jid ?? account, on: account, vcard: vcard);
                    onSuccess?(vcard);
                }
            case .failure(let errorCondition):
                onError?(errorCondition);
            }
        });
    }
    
    open func retrieveVCard(account: BareJID, for jid: JID?, completionHandler: @escaping (Result<VCard,ErrorCondition>)->Void) {
        guard let client = getClient(forJid: account) else {
            completionHandler(.failure(ErrorCondition.service_unavailable));
            return;
        }
        if let vcard4Module: VCard4Module = client.modulesManager.getModule(VCard4Module.ID) {
            retrieveVCard(module: vcard4Module, for: jid, completionHandler: { result in
                switch result {
                case .success(let vcard):
                    completionHandler(.success(vcard));
                case .failure(let errorCondition):
                    if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
                        self.retrieveVCard(module: vcardTempModule, for: jid, completionHandler: completionHandler);
                    } else {
                        completionHandler(.failure(errorCondition));
                    }
                }
            });
        } else if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
            retrieveVCard(module: vcardTempModule, for: jid, completionHandler: completionHandler);
        } else {
            completionHandler(.failure(.undefined_condition));
        }
    }
    
    private func retrieveVCard(module: VCardModuleProtocol, for jid: JID?, completionHandler: @escaping (Result<VCard,ErrorCondition>)->Void) {
        module.retrieveVCard(from: jid, completionHandler: completionHandler);
    }
        
    open func publishVCard(account: BareJID, vcard: VCard, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        guard let client = getClient(forJid: account) else {
            completionHandler(.failure(ErrorCondition.service_unavailable));
            return;
        }
        
        if let vcard4Module: VCard4Module = client.modulesManager.getModule(VCard4Module.ID) {
            vcard4Module.publishVCard(vcard, completionHandler: { result in
                switch result {
                case .success(_):
                    completionHandler(.success(Void()));
                case .failure(let error):
                    if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
                        vcardTempModule.publishVCard(vcard, completionHandler: completionHandler);
                    } else {
                        completionHandler(.failure(error));
                    }
                }
            });
        } else if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
            vcardTempModule.publishVCard(vcard, completionHandler: completionHandler);
        } else {
            completionHandler(.failure(ErrorCondition.service_unavailable));
        }
    }
    
}
