//
// XMPPError+LocalizedError.swift
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

import Foundation
import TigaseSwift

extension XMPPError: LocalizedError {

    public var errorDescription: String? {
        let codes = [applicationCondition?.description, condition.rawValue].compactMap({ $0 }).joined(separator: ", ");
        if let message = self.message {
            return String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@ (%@)", comment: "xmpp error description with message and codes"), message, codes)
        } else {
            return String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "xmpp error description with codes"), codes)
        }
    }

    public var recoverySuggestion: String? {
        return condition.recoverySuggestion;
    }

}

extension ErrorCondition: LocalizedError {

    public var recoverySuggestion: String? {
        switch type {
        case .auth:
            return NSLocalizedString("Retry after providing credentials", comment: "xmpp error condition auth type recovery suggestion")
        case .cancel:
            return nil;
        case .continue:
            return nil;
        case .modify:
            return NSLocalizedString("Provided data were not accepted. Please check provided values." , comment: "xmpp error condition modify type recovery suggestion")
        case .wait:
            return NSLocalizedString("Try again later." , comment: "xmpp error condition wait type recovery suggestion")
        }
    }
}
