//
// DnsSrvDiskCache.swift
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
import Combine

open class DNSSrvDiskCache: DNSSrvResolverWithCache.DiskCache {
    
    private var cancellable: AnyCancellable?;
    
    public override init(cacheDirectoryName: String) {
        super.init(cacheDirectoryName: cacheDirectoryName);
        self.cancellable = AccountManager.accountEventsPublisher.sink(receiveValue: { event in
            switch event {
            case .disabled(let account), .removed(let account):
                self.store(for: account.name.domain, result: nil);
            case .enabled(_):
                break;
            }
        });
    }
    
    @objc fileprivate func accountChanged(_ notification: Notification) {
        guard let account = notification.object as? AccountManager.Account else {
            return;
        }
        guard !(AccountManager.getAccount(for: account.name)?.active ?? false) else {
            return;
        }
        
        self.store(for: account.name.domain, result: nil);
    }
}
