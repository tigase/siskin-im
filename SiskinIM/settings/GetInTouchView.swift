//
// GetInTouchView.swift
//
// Siskin IM
// Copyright (C) 2023 "Tigase, Inc." <office@tigase.com>
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

struct GetInTouchView: View {
        
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Application", comment: "label"))) {
                link(image: Image(systemName: "safari"), label: NSLocalizedString("Website", comment: "label for website link/button"), destination: "https://siskin.im")
                link(image: Image(systemName: "safari"), label: NSLocalizedString("GitHub", comment: "label for opening GitHub"), destination: "https://github.com/tigase/siskin-im")
                linkLabel(image: Image(systemName: "ellipsis.bubble"), label: NSLocalizedString("XMPP Channel", comment: "label for opening XMPP channel")).onTapGesture {
                    (UIApplication.shared.delegate as! AppDelegate).open(xmppUri: AppDelegate.XmppUri(jid: JID("tigase@muc.tigase.org"), action: .join, dict: nil), action: .join);
                }
            }
            Section(header: Text(NSLocalizedString("Company", comment: "label"))) {
                link(image: Image(systemName: "safari"), label: NSLocalizedString("Website", comment: "label for website link/button"), destination: "https://tigase.net")
                link(image: Image(systemName: "safari"), label: NSLocalizedString("Twitter", comment: "label for opening Twitter"), destination: "https://twitter.com/tigase")
                link(image: Image(systemName: "safari"), label: NSLocalizedString("Mastodon", comment: "label for opening Mastodon"), destination: "https://fosstodon.org/@tigase")
            }
        }.navigationBarTitle(NSLocalizedString("Get in touch", comment: "label for button"))
    }
    
    func linkLabel(image: Image, label: String) -> some View {
        HStack {
            image.accentColor(Color("tintColor"))
            Text(label).foregroundColor(.primary)
        }
    }

    func link(image: Image, label: String, destination: String) -> some View {
        return Link(destination: URL(string: destination)!, label: {
            linkLabel(image: image, label: label)
        }).buttonStyle(.borderless)
    }
}

struct GetInTouchView_Previews: PreviewProvider {
    static var previews: some View {
        GetInTouchView()
    }
}
