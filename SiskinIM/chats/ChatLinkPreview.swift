//
// ChatLinkPreview.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

class ChatLinkPreview: ChatEntry {
    
    let url: String;
    
    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, url: String, authorNickname: String?, authorJid: BareJID?, encryption: MessageEncryption, encryptionFingerprint: String?, error: String?) {
        self.url = url;
        super.init(id: id, timestamp: timestamp, account: account, jid: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error);
    }
    
    override func copyText(withTimestamp: Bool, withSender: Bool) -> String? {
        return nil;
    }
}
