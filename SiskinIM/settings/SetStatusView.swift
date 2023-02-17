//
// SetStatusView.swift
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

struct SetStatusView: View {

    let statusNames: [Presence.Show: String] = [
        .chat : NSLocalizedString("Chatty", comment: "presence status"),
        .online : NSLocalizedString("Online", comment: "presence status"),
        .away : NSLocalizedString("Away", comment: "presence status"),
        .xa : NSLocalizedString("Extended away", comment: "presence status"),
        .dnd : NSLocalizedString("Do not disturb", comment: "presence status"),
    ];
    let statuses: [Presence.Show] = [.chat, .online, .away, .xa, .dnd];

    @State
    var automatic: Bool;
    
    @State
    var status: Presence.Show;
    
    @State
    var message = ""
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Status", comment: "label for status group")), footer: Text(NSLocalizedString("Automatic status will be set according to the application state without a need of user interaction.", comment: "description of automatic status behaviour"))) {
                Toggle(isOn: $automatic, label: {
                    Text("Automatic")
                })
                if !automatic {
                    Menu {
                        statusItem(show: .chat)
                        statusItem(show: .online)
                        statusItem(show: .away)
                        statusItem(show: .xa)
                        statusItem(show: .dnd)
                    } label: {
                        Label(title: {
                            Text(statusNames[status]!)
                        }, icon: {
                            Image(systemName: AvatarStatusView.statusImageName(status))
                        }).foregroundColor(Color(AvatarStatusView.statusColor(status)))
                    }
                }
            }
            Section(header: Text(NSLocalizedString("Status message", comment: "header label for section related to setting presence status message")), footer: Text(NSLocalizedString("This message will be visible to you contacts when you are online", comment: "description of status message"))) {
                TextField(NSLocalizedString("Status message", comment: "header label for section related to setting presence status message"), text: $message)
            }
        }.navigationTitle(NSLocalizedString("Status", comment: "label for status group")).navigationBarTitleDisplayMode(.inline).onDisappear(perform: {
            Settings.statusMessage = message.trimmingCharacters(in: .whitespacesAndNewlines);
            Settings.statusType = automatic ? nil : status;
        })
    }
    
    func statusItem(show: Presence.Show) -> some View {
        Button(action: {
            self.status = show;
        }) {
            Label(title: {
                Text(statusNames[show]!);
            }, icon: {
                Image(uiImage: AvatarStatusView.getStatusImage(show)!);
            })
        }
    }
}

struct SetStatusView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SetStatusView(automatic: false, status: .online, message: "Hello World!")
        }
    }
}
