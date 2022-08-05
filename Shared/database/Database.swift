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
import TigaseLogging

extension DatabasePool {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "sqlite");
    
    convenience init(dbUrl: URL, schemaMigrator: DatabaseSchemaMigrator? = nil) throws {
        try self.init(configuration: Configuration(path: dbUrl.path, schemaMigrator: schemaMigrator));
        DatabasePool.logger.info("Initialized database: \(dbUrl.path)");
    }
}

extension Database {
    
    public static func openSharedDatabase(at url: URL) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil);
        var coordinatorError: NSError?;
        var dbPool: DatabasePool?;
        var dbError: Error?;
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError, byAccessor: { url in
            do {
                dbPool = try DatabasePool(dbUrl: url, schemaMigrator: DatabaseMigrator());
            } catch {
                dbError = error;
            }
        })
        if let error = dbError ?? coordinatorError {
            throw error;
        }
        return dbPool!;
    }
    
    public static func mainDatabaseUrl() -> URL {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("siskinim_main.db");
    }
    
    public static let main: DatabasePool = {
        return try! openSharedDatabase(at: mainDatabaseUrl());
    }();
    
}

extension JID: DatabaseConvertibleStringValue {
    
    public func encode() -> String {
        return self.description;
    }
    
}

extension BareJID: DatabaseConvertibleStringValue {
    
    public func encode() -> String {
        return self.description;
    }
    
}

extension Element: DatabaseConvertibleStringValue {
    public func encode() -> String {
        return self.description;
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
