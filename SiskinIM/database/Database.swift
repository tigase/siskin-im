//
// Database.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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

extension Database {
    
    static let main: DatabasePool = {
        return try! DatabasePool(dbUrl: mainDatabaseUrl(), schemaMigrator: DatabaseMigrator());
    }();
    
}

extension DatabasePool {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "sqlite");
    
    convenience init(dbUrl: URL, schemaMigrator: DatabaseSchemaMigrator? = nil) throws {
        try self.init(configuration: Configuration(path: dbUrl.path, schemaMigrator: schemaMigrator));
        DatabasePool.logger.info("Initialized database: \(dbUrl.path)");
    }
}


