//
// NotificationsView.swift
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
import Shared

struct NotificationsView: View {
    
    @Setting(\.enablePush) var enablePush;
    @Setting(\.notificationsFromUnknown) var notificationsFromUnknown;
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Push Notifications", comment: "section label")), footer: Text(UIApplication.shared.isRegisteredForRemoteNotifications ?
                                                                                                            NSLocalizedString("If enabled, you will receive notifications of new messages or calls even if SiskinIM is in background. SiskinIM servers will forward those notifications for you from XMPP servers.", comment: "push notifications option description") : NSLocalizedString("You need to allow application to show notifications and for background refresh.", comment: "push notifications not allowed warning"))
                    , content: {
                HStack {
                    Toggle(NSLocalizedString("Enable", comment: "toggle label"), isOn: .init(get: {
                        return UIApplication.shared.isRegisteredForRemoteNotifications && (self.enablePush ?? false);
                    }, set: { newValue in
                        self.$enablePush.wrappedValue = newValue;
                    })).disabled(!(anyAccountHasPush() && UIApplication.shared.isRegisteredForRemoteNotifications))
                }
            })
            Section(header: Text(NSLocalizedString("Notifications from unknown", comment: "section label")), footer: Text(NSLocalizedString("Show notifications from people not in your contact list", comment: "notifications from unknown description")), content: {
                HStack {
                    Toggle(NSLocalizedString("Enable", comment: "toggle label"), isOn: $notificationsFromUnknown)
                }
            })
        }.navigationTitle(NSLocalizedString("Notifications", comment: "view label")).navigationBarTitleDisplayMode(.inline)
    }
    
    private func anyAccountHasPush() -> Bool {
        return AccountManager.accounts.contains(where: { $0.additional.knownServerFeatures.contains(.push) })
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotificationsView()
        }
    }
}
