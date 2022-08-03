//
// CertificateErrorAlert.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import Martin

class CertificateErrorAlert {
    
    public static func create(domain: String, certData: SslCertificateInfo, onAccept: (()->Void)?, onDeny: (()->Void)?) -> UIAlertController {
        return create(domain: domain, certName: certData.details.name, certHash: certData.details.fingerprintSha1, issuerName: certData.issuer?.name, issuerHash: certData.issuer?.fingerprintSha1, onAccept: onAccept, onDeny: onDeny);
    }
    
    public static func create(domain: String, certName: String, certHash: String, issuerName: String?, issuerHash: String?, onAccept: (()->Void)?, onDeny: (()->Void)?) -> UIAlertController {
        let issuer = issuerName != nil ? String.localizedStringWithFormat(NSLocalizedString("\nissued by\n%@\n with fingerprint\n%@", comment: "ssl certificate info - issue part"), issuerName!, issuerHash!) : "";
        let alert = UIAlertController(title: NSLocalizedString("Certificate issue", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Server for domain %@ provided invalid certificate for %@\n with fingerprint\n%@%@.\nDo you trust this certificate?", comment: "ssl certificate alert dialog body"), domain, certName, certHash, issuer), preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .cancel, handler: CertificateErrorAlert.wrapActionHandler(onDeny)));
        alert.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .destructive, handler: CertificateErrorAlert.wrapActionHandler(onAccept)));
        return alert;
    }
    
    fileprivate static func wrapActionHandler(_ action: (()->Void)?) -> ((UIAlertAction)->Void)? {
        guard action != nil else {
            return nil;
        }
        return {(aa) in action!(); };
    }
    
}
