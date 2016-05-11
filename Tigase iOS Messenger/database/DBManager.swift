//
// DBManager.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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

let SQLITE_TRANSIENT = unsafeBitCast(-1, sqlite3_destructor_type.self)

public class DBConnection {
    
    private var handle_:COpaquePointer = nil;
    public var handle:COpaquePointer {
        get {
            return handle_;
        }
    }

    public var lastInsertRowId: Int? {
        let rowid = sqlite3_last_insert_rowid(handle);
        return rowid > 0 ? Int(rowid) : nil;
    }
    
    public var changesCount: Int {
        return Int(sqlite3_changes(handle));
    }
    
    init(dbFilename:String) throws {
        let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true);
        let documentDirectory = paths[0];
        let path = documentDirectory.stringByAppendingString("/" + dbFilename);
        
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE;
        
        try check(sqlite3_open_v2(path, &handle_, flags | SQLITE_OPEN_FULLMUTEX, nil));
    }
    
    deinit {
        sqlite3_close(handle);
    }
    
    public func execute(query: String) throws {
        try check(sqlite3_exec(handle, query, nil, nil, nil));
    }
    
    public func prepareStatement(query: String) throws -> DBStatement {
        return try DBStatement(connection: self, query: query);
    }
    
    
    private func check(result:Int32, statement:DBStatement? = nil) throws -> Int32 {
        guard let error = DBResult(errorCode: result, connection: self, statement: statement) else {
            return result;
        }
        
        throw error;
    }

}

public enum DBResult: ErrorType {

    private static let successCodes = [ SQLITE_OK, SQLITE_ROW, SQLITE_DONE ];
    
    case Error(message:String, code: Int32, statement:DBStatement?)
    
    init?(errorCode: Int32, connection: DBConnection, statement:DBStatement?) {
        guard !DBResult.successCodes.contains(errorCode) else {
            return nil;
        }
        
        let message = String.fromCString(sqlite3_errmsg(connection.handle))!;
        self = Error(message: message, code: errorCode, statement: statement);
    }
    
}

public class DBStatement {

    private var handle:COpaquePointer = nil;
    private let connection:DBConnection;
    
    public lazy var columnCount:Int = Int(sqlite3_column_count(self.handle));
    
    public lazy var columnNames:[String] = (0..<Int32(self.columnCount)).map { (idx:Int32) -> String in
        return String.fromCString(sqlite3_column_name(self.handle, idx))!;
    }
    
    public lazy var cursor:DBCursor = DBCursor(statement: self);
    
    public var lastInsertRowId: Int? {
        return connection.lastInsertRowId;
    }
    
    public var changesCount: Int {
        return connection.changesCount;
    }
    
    init(connection:DBConnection, query:String) throws {
        self.connection = connection;
        try connection.check(sqlite3_prepare(connection.handle, query, -1, &handle, nil));
    }

    deinit {
        sqlite3_finalize(handle);
    }

    public func step() throws -> Bool  {
        let result = try connection.check(sqlite3_step(handle));
        return result == SQLITE_ROW;
    }
    
    public func bind(params:Any?...) throws -> DBStatement {
        try bind(params);
        return self;
    }
    
    public func bind(params:[String:Any?]) throws -> DBStatement {
        reset()
        for (k,v) in params {
            let pos = sqlite3_bind_parameter_index(handle, ":"+k);
            if pos == 0 {
                print("got pos = 0, while parameter count = ", sqlite3_bind_parameter_count(handle));
            }
            try bind(v, pos: pos);
        }
        return self;
    }
    
    public func bind(params:[Any?]) throws -> DBStatement {
        reset()
        for pos in 1...params.count {
            try bind(params[pos-1], atIndex: pos);
        }
        return self;
    }
    
    public func bind(value:Any?, atIndex:Int) throws -> DBStatement {
        try bind(value, pos: Int32(atIndex));
        return self;
    }
    
    private func bind(value_:Any?, pos:Int32) throws {
        var r:Int32 = SQLITE_OK;
        if value_ == nil {
            r = sqlite3_bind_null(handle, pos);
        } else if let value:Any = value_ {
            switch value {
            case let v as [UInt8]:
                r = sqlite3_bind_blob(handle, pos, v, Int32(v.count), SQLITE_TRANSIENT);
            case let v as NSData:
                r = sqlite3_bind_blob(handle, pos, v.bytes, Int32(v.length), SQLITE_TRANSIENT);
            case let v as Double:
                r = sqlite3_bind_double(handle, pos, v);
            case let v as Int:
                r = sqlite3_bind_int64(handle, pos, Int64(v));
            case let v as Bool:
                r = sqlite3_bind_int(handle, pos, Int32(v ? 1 : 0));
            case let v as String:
                r = sqlite3_bind_text(handle, pos, v, -1, SQLITE_TRANSIENT);
            case let v as NSDate:
                let timestamp = Int64(v.timeIntervalSince1970 * 1000);
                r = sqlite3_bind_int64(handle, pos, timestamp);
            default:
                throw DBResult.Error(message: "Unsupported type \(value.self) for parameter \(pos)", code: SQLITE_FAIL, statement: self);
            }
        } else {
            sqlite3_bind_null(handle, pos)
        }
        try check(r);
    }
    
    public func execute(params:[String:Any?]) throws -> DBStatement? {
        try bind(params);
        return try execute();
    }
    
    public func execute(params:Any?...) throws -> DBStatement? {
        return try execute(params);
    }

    private func execute(params:[Any?]) throws -> DBStatement? {
        if params.count > 0 {
            try bind(params);
        }
        reset(false);
        return try step() ? self : nil;
    }
    
    public func query(params:[String:Any?]) throws -> DBCursor? {
        return try execute(params)?.cursor;
    }

    public func query(params:Any?...) throws -> DBCursor? {
        return try execute(params)?.cursor;
    }

    public func query(params:[String:Any?], forEachRow: (DBCursor)->Bool) throws {
        if let cursor = try execute(params)?.cursor {
            repeat {
                if !forEachRow(cursor) {
                    break;
                }
            } while cursor.next();
        }
    }
    
    public func query(params:Any?..., forEachRow: (DBCursor)->Bool) throws {
        if let cursor = try execute(params)?.cursor {
            repeat {
                if !forEachRow(cursor) {
                    break;
                }
            } while cursor.next();
        }
    }

    public func query(params:[String:Any?], forEachRow: (DBCursor)->Void) throws {
        if let cursor = try execute(params)?.cursor {
            repeat {
                forEachRow(cursor);
            } while cursor.next();
        }
    }
    
    public func query(params:Any?..., forEachRow: (DBCursor)->Void) throws {
        if let cursor = try execute(params)?.cursor {
            repeat {
                forEachRow(cursor);
            } while cursor.next();
        }
    }
    
    public func insert(params:Any?...) throws -> Int? {
        return try execute(params)?.lastInsertRowId;
    }

    public func insert(params:[String:Any?]) throws -> Int? {
        return try execute(params)?.lastInsertRowId;
    }
    
    public func update(params:Any?...) throws -> Int {
        try execute(params);
        return changesCount;
    }

    public func update(params:[String:Any?]) throws -> Int {
        try execute(params);
        return changesCount;
    }
    
    public func scalar(params:Any?...) throws -> Int? {
        return try execute(params)?.cursor[0];
    }

    public func scalar(params:[String:Any?]) throws -> Int? {
        return try execute(params)?.cursor[0];
    }
    
    public func reset(bindings:Bool=true) {
        sqlite3_reset(handle);
        if bindings {
            sqlite3_clear_bindings(handle);
        }
    }
    
    private func check(result:Int32) throws -> Int32 {
        return try connection.check(result, statement: self);
    }
    
}

public class DBCursor {

    private let handle:COpaquePointer;

    public lazy var columnCount:Int = Int(sqlite3_column_count(self.handle));
    
    public lazy var columnNames:[String] = (0..<Int32(self.columnCount)).map { (idx:Int32) -> String in
        return String.fromCString(sqlite3_column_name(self.handle, idx))!;
    }
    
    init(statement:DBStatement) {
        self.handle = statement.handle;
    }

    subscript(index: Int) -> Double {
        return sqlite3_column_double(handle, Int32(index));
    }
    
    subscript(index: Int) -> Int {
        return Int(sqlite3_column_int64(handle, Int32(index)));
    }

    subscript(index: Int) -> String? {
        let ptr = sqlite3_column_text(handle, Int32(index));
        if ptr == nil {
            return nil;
        }
        return String.fromCString(UnsafePointer(ptr));
    }
    
    subscript(index: Int) -> Bool {
        return sqlite3_column_int64(handle, Int32(index)) != 0;
    }
    
    subscript(index: Int) -> [UInt8]? {
        let idx = Int32(index);
        let origPtr = sqlite3_column_blob(handle, idx);
        if origPtr == nil {
            return nil;
        }
        let ptr = UnsafePointer<UInt8>(origPtr);
        let count = Int(sqlite3_column_bytes(handle, idx));
        return DBCursor.convert(count, data: ptr);
    }

    subscript(index: Int) -> NSData? {
        let idx = Int32(index);
        let origPtr = sqlite3_column_blob(handle, idx);
        if origPtr == nil {
            return nil;
        }
        let count = Int(sqlite3_column_bytes(handle, idx));
        return NSData(bytes: origPtr, length: count);
    }
    
    subscript(index: Int) -> NSDate {
        let timestamp = Double(sqlite3_column_int64(handle, Int32(index))) / 1000;
        return NSDate(timeIntervalSince1970: timestamp);
    }
    
    subscript(column: String) -> Double? {
        return forColumn(column) {
            return self[$0];
        }
    }

    subscript(column: String) -> Int? {
//        return forColumn(column) {
//            let v:Int? = self[$0];
//            print("for \(column), position \($0) got \(v)")
//            return v;
//        }
        if let idx = columnNames.indexOf(column) {
            return self[idx];
        }
        return nil;
    }

    subscript(column: String) -> String? {
        return forColumn(column) {
            return self[$0];
        }
    }

    subscript(column: String) -> Bool? {
        return forColumn(column) {
            return self[$0];
        }
    }

    subscript(column: String) -> [UInt8]? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> NSData? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> NSDate? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    private func forColumn<T>(column:String, exec:(Int)->T?) -> T? {
        if let idx = columnNames.indexOf(column) {
            return exec(idx);
        }
        return nil;
    }
    
    private static func convert<T>(count: Int, data: UnsafePointer<T>) -> [T] {
        let buffer = UnsafeBufferPointer(start: data, count: count);
        return Array(buffer)
    }
    
    public func next() -> Bool {
        return sqlite3_step(handle) == SQLITE_ROW;
    }
    
    public func next() -> DBCursor? {
        return next() ? self : nil;
    }
}