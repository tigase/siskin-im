//
// DBSchemaManager.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
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

public class DBSchemaManager {
    
    static let CURRENT_VERSION = 2;
    
    fileprivate let dbConnection: DBConnection;
    
    init(dbConnection: DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    open func upgradeSchema() throws {
        var version = 1;// try! getSchemaVersion();
        while (version < DBSchemaManager.CURRENT_VERSION) {
            switch version {
            case 0:
                try loadSchemaFile(fileName: "/db-schema-1.sql");
                do {
                    try dbConnection.execute("select preview from chat_history");
                } catch {
                    try dbConnection.execute("ALTER TABLE chat_history ADD COLUMN preview TEXT");
                }
                do {
                    try dbConnection.execute("select error from chat_history");
                } catch {
                    try dbConnection.execute("ALTER TABLE chat_history ADD COLUMN error TEXT;");
                }
                try cleanUpDuplicatedChats();
            case 1:
                try loadSchemaFile(fileName: "/db-schema-2.sql");
                try cleanUpDuplicatedChats();
            default:
                break;
            }
            version = try! getSchemaVersion();
        }
    }
    
    open func getSchemaVersion() throws -> Int {
        return try self.dbConnection.prepareStatement("PRAGMA user_version").scalar() ?? 0;
    }
    
    fileprivate func loadSchemaFile(fileName: String) throws {
        let resourcePath = Bundle.main.resourcePath! + fileName;
        print("loading SQL from file", resourcePath);
        let dbSchema = try String(contentsOfFile: resourcePath, encoding: String.Encoding.utf8);
        print("read schema:", dbSchema);
        try dbConnection.execute(dbSchema);
        print("loaded schema from file", fileName);
    }
    
    fileprivate func cleanUpDuplicatedChats() throws {
        // deal with duplicated chats for the same bare jid
        print("looking for duplicated chats...");
        let duplicates: [(String, String, Int)] = try dbConnection.prepareStatement("select min(c.id) as id, c.account, c.jid from (select count(id) as count, account, jid from chats group by account, jid) x inner join chats c on c.account = x.account and c.jid = x.jid where count > 1 group by c.account, c.jid").query() { (cursor) -> (String, String, Int) in
            let account: String = cursor["account"]!;
            let jid: String = cursor["jid"]!;
            let id: Int = cursor["id"] ?? 0;
            print("account", account, "jid", jid, "id", id);
            return (account, jid, id);
        }
        print("found duplicates", duplicates);
        try duplicates.forEach({ (account, jid, idToLeave) in
            let removed = try dbConnection.prepareStatement("delete from chats where account = ? and jid = ? and id <> :id").scalar(account, jid, idToLeave);
            print("for account", account, "and jid", jid, "removed", removed, "duplicated chats");
        });
        print("duplicated chats cleanup finished!");

    }
}
