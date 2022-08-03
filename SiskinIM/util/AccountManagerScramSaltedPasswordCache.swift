//
// AccountManagerScramSaltedPasswordCache.swift
//
// Siskin IM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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

open class AccountManagerScramSaltedPasswordCache: ScramSaltedPasswordCacheProtocol {
    
    public init() {
    }
    
    public func getSaltedPassword(for context: Context, id: String) -> [UInt8]? {
        guard let salted = AccountManager.getAccount(for: context.userBareJid)?.saltedPassword else {
            return nil;
        }
        return salted.id == id ? salted.value : nil;
    }
    
    public func store(for context: Context, id: String, saltedPassword: [UInt8]) {
        setSaltedPassword(AccountManager.SaltEntry(id: id, value: saltedPassword), for: context);
    }
    
    public func clearCache(for context: Context) {
        setSaltedPassword(nil, for: context)
    }
    
    fileprivate func setSaltedPassword(_ value: AccountManager.SaltEntry?, for context: Context) {
        guard var account = AccountManager.getAccount(for: context.userBareJid) else {
            return;
        }
        
        account.saltedPassword = value;
        try? AccountManager.save(account: account, reconnect: false);
    }
    
}
