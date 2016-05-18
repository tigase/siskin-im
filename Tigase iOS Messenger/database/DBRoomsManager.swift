//
//  DBRoomsManager.swift
//  Tigase-iOS-Messenger
//
//  Created by Andrzej Wójcik on 16.05.2016.
//  Copyright © 2016 Tigase, Inc. All rights reserved.
//

import Foundation
import TigaseSwift

public class DBRoomsManager: AbstractRoomsManager {
    
    private let store: DBChatStore;
    
    public init(store: DBChatStore) {
        self.store = store;
    }
    
    public override func createRoomInstance(roomJid: BareJID, nickname: String, password: String?) -> Room {
        let room = super.createRoomInstance(roomJid, nickname: nickname, password: password);
        return store.open(context.sessionObject, chat: room)!;
    }
    
    public override func initialize() {
        guard self.getRooms().count == 0 else {
            return;
        }
        let rooms:[Room] = store.getAll(context.sessionObject);
        for room in rooms {
            register(room);
        }
    }
    
    public override func remove(room: Room) {
        if store.close(room) {
            super.remove(room);
        }
    }
}

class DBRoom: Room {
    
    var id: Int? = nil;
    
}