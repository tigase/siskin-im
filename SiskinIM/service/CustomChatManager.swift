//
// CustomChatManager.swift
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
import TigaseSwift

class CustomChatManager: DefaultChatManager {
    
    public override init(context: Context, chatStore:ChatStore) {
        super.init(context: context, chatStore: chatStore)
    }
    
    override func getChat(with jid: JID, thread: String?) -> Chat? {
        return chatStore.getChat(with: jid.bareJid, filter: { (c) -> Bool in
            return c.jid.bareJid == jid.bareJid;
        });
    }
    
}

