//
// AppearanceSettingsView.swift
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
import Combine

struct AppearanceSettingsView: View {

    @State private var appearance: Appearance;
    private var cancellables: Set<AnyCancellable> = [];
    
    init() {
        self.appearance = Settings.appearance;
        let state = self._appearance;
        Settings.$appearance.sink(receiveValue: { newValue in
            state.wrappedValue = newValue;
        }).store(in: &cancellables);
    }
    
    var body: some View {
        List {
            NavigationLink(destination: {
                ItemSelectorView(message: NSLocalizedString("Select appearance", comment: "select application appearance"), options: [.auto, .dark, .light], selected: Settings.appearance, onChange: { value in
                    Settings.appearance = value;
                }).navigationBarTitle(NSLocalizedString("Appearance", comment: "appearance settings"))
            }, label: {
                HStack {
                    Text(NSLocalizedString("Appearance", comment: "appearance settings"))
                    Spacer()
                    Text(appearance.label)
                }
            })
            
            Section(content: {                NavigationLink(destination: {
                ItemSelectorView(message: NSLocalizedString("Select application icon", comment: "selection application icon information"), options: [.default, .simple], selected: Settings.appIcon, onChange: { value in
                    Settings.appIcon = value;
                    let strValue = value == .default ? nil : value.rawValue;
                    if UIApplication.shared.alternateIconName != strValue {
                        UIApplication.shared.setAlternateIconName(strValue) { error in
                            if error != nil {
                                Settings.appIcon = SettingsStore.AppIcon(rawValue: UIApplication.shared.alternateIconName ?? "") ?? .default;
                            }
                        }
                    }
                }).navigationBarTitle(NSLocalizedString("Icon", comment: "application icon"))
            }, label: {
                HStack {
                    Image(uiImage: Settings.appIcon.icon!).cornerRadius(10)
                    Text(Settings.appIcon.label)
                    Spacer()
                }
            })
            }, header: {
                Text(NSLocalizedString("Icon", comment: "application icon"))
            })
        }.navigationBarTitle(NSLocalizedString("Appearance", comment: "appearance settings"))
    }
    
}

struct AppearanceSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AppearanceSettingsView()
    }
}
