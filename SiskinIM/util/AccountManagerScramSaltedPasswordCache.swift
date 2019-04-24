//
// AccountManagerScramSaltedPasswordCache.swift
//
// Tigase iOS Messenger
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation
import TigaseSwift

open class AccountManagerScramSaltedPasswordCache: ScramSaltedPasswordCacheProtocol {
    
    public init() {
    }
    
    public func getSaltedPassword(for sessionObject: SessionObject, id: String) -> [UInt8]? {
        guard let salted = AccountManager.getAccount(for: sessionObject)?.saltedPassword else {
            return nil;
        }
        return salted.id == id ? salted.value : nil;
    }
    
    public func store(for sessionObject: SessionObject, id: String, saltedPassword: [UInt8]) {
        setSaltedPassword(AccountManager.SaltEntry(id: id, value: saltedPassword), for: sessionObject);
    }
    
    public func clearCache(for sessionObject: SessionObject) {
        setSaltedPassword(nil, for: sessionObject)
    }
    
    fileprivate func setSaltedPassword(_ value: AccountManager.SaltEntry?, for sessionObject: SessionObject) {
        guard let account = AccountManager.getAccount(for: sessionObject) else {
            return;
        }
        
        account.saltedPassword = value;
        AccountManager.updateAccount(account, notifyChange: false);
    }
    
}
