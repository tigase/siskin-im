//
// NotificationCategory.swift
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

public enum NotificationCategory: String {
    case UNKNOWN
    case ERROR
    case MESSAGE
    case SUBSCRIPTION_REQUEST
    case MUC_ROOM_INVITATION
    case CALL
    case UNSENT_MESSAGES

    public static func from(identifier: String?) -> NotificationCategory {
        guard let str = identifier else {
            return .UNKNOWN;
        }
        return NotificationCategory(rawValue: str) ?? .UNKNOWN;
    }
}
