//
// MediaHelper.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

import UIKit
import AVKit
import Shared

extension MediaHelper {
    
    static func askImageQuality(controller: UIViewController, forceQualityQuestion askQuality: Bool) async throws -> ImageQuality {
        if let quality = askQuality ? nil : Settings.imageQuality {
            return quality;
        } else {
            return try await withUnsafeThrowingContinuation({ continuation in
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: NSLocalizedString("Select quality", comment: "media quality selection instruction"), message: nil, preferredStyle: .alert);
                    
                    let values: [ImageQuality] = [.original, .highest, .high, .medium, .low];
                    for value in  values {
                        alert.addAction(UIAlertAction(title: value.rawValue.capitalized, style: .default, handler: { _ in
                            continuation.resume(returning: value)
                        }));
                    }
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
                        continuation.resume(throwing: ShareError.cancelled)
                    }))
                    controller.present(alert, animated: true);
                }
            })
        }
    }
    
    static func askVideoQuality(controller: UIViewController, forceQualityQuestion askQuality: Bool) async throws -> VideoQuality {
        if let quality = askQuality ? nil : Settings.videoQuality {
            return quality;
        } else {
            return try await withUnsafeThrowingContinuation({ continuation in
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: NSLocalizedString("Select quality", comment: "media quality selection instruction"), message: nil, preferredStyle: .alert);
                    
                    let values: [VideoQuality] = [.original, .high, .medium, .low];
                    for value in  values {
                        alert.addAction(UIAlertAction(title: value.rawValue.capitalized, style: .default, handler: { _ in
                            continuation.resume(returning: value)
                        }));
                    }
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
                        continuation.resume(throwing: ShareError.cancelled)
                    }))
                    controller.present(alert, animated: true);
                }
            })
        }
    }
    
}
