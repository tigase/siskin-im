//
// AboutApplicationView.swift
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

struct AboutApplicationView: View {
    var body: some View {
        GeometryReader { gp in
            VStack {
                let size = min(gp.size.height, gp.size.width) * 0.7;
                VStack {
                    Image("appLogo").resizable().aspectRatio(1.0, contentMode: .fit).cornerRadius(10)
                    Text("Siskin IM").font(Font.largeTitle).foregroundColor(Color("tintColor"))
                    Text(String.localizedStringWithFormat(NSLocalizedString("Version: %@", comment: "version of the app"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")).font(.subheadline).foregroundColor(.secondary)
                }.padding([.top], 10).frame(maxHeight: size)
                List {
                    NavigationLink(destination: {
                        LicencesView()
                    }, label: {
                        Text(NSLocalizedString("Licences", comment: "title for licences view"))
                    })
                }
            }.background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
                .navigationTitle(NSLocalizedString("About application", comment: "title for about application view"))
        }
    }
}

struct AboutApplicationView_Previews: PreviewProvider {
    static var previews: some View {
        AboutApplicationView()
    }
}
