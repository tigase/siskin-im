//
// LicencesView.swift
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

struct LicencesView: View {
    var body: some View {
        ScrollView(.vertical) {
            Text(try! NSAttributedString(url: Bundle.main.url(forResource: "Licences", withExtension: "rtf")!, documentAttributes: nil).string).font(.caption).padding()
        }.navigationTitle(NSLocalizedString("Licences", comment: "title for licences view"))
    }
}

struct LicencesView_Previews: PreviewProvider {
    static var previews: some View {
        LicencesView()
    }
}
