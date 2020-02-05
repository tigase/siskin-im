//
// AccountQRCodeController.swift
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
import TigaseSwift

class AccountQRCodeController: UIViewController {
    
    @IBOutlet var qrCodeView: UIImageView!;
    
    var account: BareJID?;
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        if let account = self.account {
            var dict: [String: String]? = nil;
            if let vcard = XmppService.instance.dbVCardsCache.getVCard(for: account) {
                if let fn = vcard.fn {
                    dict = ["name": fn];
                } else {
                    if let given = vcard.givenName, !given.isEmpty {
                        if let surname = vcard.surname, !surname.isEmpty {
                            dict = ["name": "\(given) \(surname)"];
                        } else {
                            dict = ["name": given];
                        }
                    } else if let surname = vcard.surname, !surname.isEmpty {
                        dict = ["name": surname];
                    } else if let nick = vcard.nicknames.first, !nick.isEmpty {
                        dict = ["name": nick];
                    }
                }
            }
            
            if let data = AppDelegate.XmppUri(jid: JID(account), action: nil, dict: dict).toURL()?.absoluteString.data(using: .ascii), let qrFilter = CIFilter(name: "CIQRCodeGenerator") {
                qrFilter.setValue(data, forKey: "inputMessage");
                let transform = CGAffineTransform(scaleX: 10, y: 10)
                if let ciImage = qrFilter.outputImage?.transformed(by: transform) {
                    let context = CIContext();
                    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                        qrCodeView.image = UIImage(cgImage: cgImage);
                    }
                }
            }
        }
    }
    
}
