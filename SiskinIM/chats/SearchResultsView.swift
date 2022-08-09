//
// SearchResultsView.swift
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

import SwiftUI
import Martin

@available(iOS 14.0, *)
struct SearchResultsView: View {
    
    var conversations: [ConversationSearchResult] = [];
    var selection: ((ConversationSearchResult)->Void)?;
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(conversations, id: \.id) { conversation in
                    ConversationSearchResultRow(conversation: conversation)
                        .scaledToFill()
                        .onTapGesture {
                            selection?(conversation)
                            //conversations.removeAll();
                    }
                }
            }
            .padding(.all, 10)
            .scaledToFill()
        }
        .background(Color("chatslistBackground"))
    }
    
}

@available(iOS 14.0, *)
struct SearchResultController_Previews: PreviewProvider {
    static var previews: some View {
        SearchResultsView(conversations: [])
    }
}

struct ConversationSearchResultRow: View {
   
    var conversation: ConversationSearchResult;
    
    var body: some View {
        HStack {
            Image(uiImage: (conversation.account != nil ? AvatarManager.instance.avatar(for: conversation.jid, on: conversation.account!) : nil) ?? UIImage.withInitials(conversation.name.initials, size: .init(width: 36, height: 36)) ?? AvatarManager.instance.defaultAvatar)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text(conversation.name)
                .font(.headline)
                .foregroundColor(.white)
                .scaledToFill()
        }
    }
    
}

struct ConversationSearchResult: Identifiable {
    
    let id: Key
    var jid: BareJID {
        return id.jid;
    }
    var account: BareJID? {
        return id.account;
    }
    let name: String;
    let displayableId: DisplayableIdProtocol?;
    
    struct Key: Hashable {
        let account: BareJID?;
        let jid: BareJID;
    }
    
    init(jid: BareJID, account: BareJID?, name: String, displayableId: DisplayableIdProtocol?) {
        id = .init(account: account, jid: jid);
        self.name = name;
        self.displayableId = displayableId;
    }
}
