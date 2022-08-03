//
// BookmarkItem.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

public struct BookmarkItem {
    
    public let account: BareJID;
    public let item: Bookmarks.Conference;
    public var jid: JID {
        return item.jid;
    }
    public var name: String {
        return item.name ?? item.jid.localPart ?? item.jid.stringValue;
    }
    public var nickname: String? {
        return item.nick;
    }
    public var password: String? {
        return item.password;
    }
    public var autojoin: Bool {
        return item.autojoin;
    }
    
}
