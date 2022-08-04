//
//  DBAccountStore.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 25/07/2022.
//  Copyright © 2022 Tigase, Inc. All rights reserved.
//

import Foundation
import Martin
import TigaseSQLite3

extension Query {
    static let accountsList = Query("SELECT name, enabled, server_endpoint, roster_version, status_message, push, last_endpoint, additional FROM accounts");
    static let accountInsert = Query("INSERT INTO accounts (name, enabled, server_endpoint, additional) VALUES (:name,:enabled,:server_endpoint,:additional)");
    static let accountDelete = Query("DELETE FROM accounts WHERE name = :name");
}

public class DBAccountStore {
    
    private static var database: DatabasePool! = nil;
    
    public static func initialize(database: DatabasePool) {
        self.database = database;
    }
    
    static func create(account: AccountManager.Account) throws {
        try database.writer({ writer in
            try writer.insert(query: .accountInsert, params: ["name": account.name, "enabled": account.enabled, "server_endpoint": account.serverEndpoint, "roster_version": account.rosterVersion, "status_message": account.statusMessage, "push": account.push, "additional": account.additional])
        })
    }
    
    static func delete(account: AccountManager.Account) throws {
        try database.writer({ writer in
            try writer.delete(query: .accountDelete, params: ["name", account.name]);
        })
    }
    
    static func update(from: AccountManager.Account, to: AccountManager.Account) throws {
        guard from.name == to.name else {
            throw XMPPError(condition: .not_acceptable);
        }
        var params: [String: Any] = [:];
        if from.enabled != to.enabled {
            params["enabled"] = to.enabled;
        }
        if from.serverEndpoint != to.serverEndpoint {
            params["server_endpoint"] = to.serverEndpoint;
        }
        if from.rosterVersion != to.rosterVersion {
            params["roster_version"] = to.rosterVersion;
        }
        if from.statusMessage != to.statusMessage {
            params["status_message"] = to.statusMessage;
        }
        if from.push != to.push {
            params["push"] = to.push;
        }
        if from.additional != to.additional {
            params["additional"] = to.additional;
        }
        
        guard !params.isEmpty else {
            return;
        }
        
        let query = "UPDATE accounts SET \(params.keys.map({ "\($0) = :\($0)" }).joined(separator: ", ")) WHERE name = :name";
        
        params["name"] = to.name;
        
        try database.writer({ writer in
            try writer.update(query, cached: false, params: params);
        })
    }
    
    static func list() throws -> [AccountManager.Account] {
        return try database.reader({ reader in
            try reader.select(query: .accountsList, params: [:]).mapAll({ cursor in
                return AccountManager.Account(name: cursor.bareJid(for: "name")!, enabled: cursor.bool(for: "enabled"), serverEndpoint: cursor.object(for: "server_endpoint"), lastEndpoint: cursor.object(for: "last_endpoint"), rosterVersion: cursor.string(for: "roster_version"), statusMessage: cursor.string(for: "status_message"), push: cursor.object(for: "push"), additional: cursor.object(for: "additional")!);
            })
        })
    }
    
}
