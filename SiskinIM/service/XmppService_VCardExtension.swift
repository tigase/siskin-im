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
        
        if let vcard4Module: VCard4Module = client.modulesManager.getModule(VCard4Module.ID) {
            refreshVCard(module: vcard4Module, for: jid, onSuccess: onSuccess, onError: {(error) in
                if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
                    self.refreshVCard(module: vcardTempModule, for: jid, onSuccess: onSuccess, onError: onError);
                } else {
                    onError?(error);
                }
            });
        } else if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
            refreshVCard(module: vcardTempModule, for: jid, onSuccess: onSuccess, onError: onError);
        } else {
            onError?(ErrorCondition.service_unavailable);
        }
    }
    
    fileprivate func refreshVCard(module: VCardModuleProtocol, for jid: BareJID?, onSuccess: ((VCard)->Void)?, onError: ((ErrorCondition?)->Void)?) {
        let account = (module as? ContextAware)!.context.sessionObject.userBareJid!;
        module.retrieveVCard(from: jid == nil ? nil : JID(jid!), onSuccess: {(vcard) in
            DispatchQueue.global(qos: .default).async() {
                self.dbVCardsCache.updateVCard(for: jid ?? account, on: account, vcard: vcard);
                onSuccess?(vcard);
            }
        }, onError: { errorCondition in
            onError?(errorCondition);
        });
    }
    
    open func publishVCard(account: BareJID, vcard: VCard, onSuccess: @escaping ()->Void, onError: @escaping (ErrorCondition?)->Void) {
        guard let client = getClient(forJid: account) else {
            onError(ErrorCondition.service_unavailable);
            return;
        }
        
        if let vcard4Module: VCard4Module = client.modulesManager.getModule(VCard4Module.ID) {
            vcard4Module.publishVCard(vcard, onSuccess: onSuccess, onError: {(error) in
                if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
                    vcardTempModule.publishVCard(vcard, onSuccess: onSuccess, onError: onError);
                } else {
                    onError(error);
                }
            });
        } else if let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
            vcardTempModule.publishVCard(vcard, onSuccess: onSuccess, onError: onError);
        } else {
            onError(ErrorCondition.service_unavailable);
        }
    }
    
}
