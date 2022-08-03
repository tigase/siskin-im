//
// Database.swift
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
import TigaseSQLite3
import Martin

extension Database {
    
    public static func mainDatabaseUrl() -> URL {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("siskinim_main.db");
    }
    
}

extension JID: DatabaseConvertibleStringValue {
    
    public func encode() -> String {
        return self.stringValue;
    }
    
}

extension BareJID: DatabaseConvertibleStringValue {
    
    public func encode() -> String {
        return self.stringValue;
    }
    
}

extension Element: DatabaseConvertibleStringValue {
    public func encode() -> String {
        return self.stringValue;
    }
}

extension Cursor {
    
    public func jid(for column: String) -> JID? {
        return JID(string(for: column));
    }
    
    public func jid(at column: Int) -> JID? {
        return JID(string(at: column));
    }
    
    public subscript(index: Int) -> JID? {
        return JID(string(at: index));
    }
    
    public subscript(column: String) -> JID? {
        return JID(string(for: column));
    }
}

extension Cursor {
    
    public func bareJid(for column: String) -> BareJID? {
        return BareJID(string(for: column));
    }
    
    public func bareJid(at column: Int) -> BareJID? {
        return BareJID(string(at: column));
    }
    
    public subscript(index: Int) -> BareJID? {
        return BareJID(string(at: index));
    }
    
    public subscript(column: String) -> BareJID? {
        return BareJID(string(for: column));
    }
}
