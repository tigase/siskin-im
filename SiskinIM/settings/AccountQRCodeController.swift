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
import Martin

class AccountQRCodeController: UIViewController {
    
    @IBOutlet var qrCodeView: UIImageView!;
    
    var account: BareJID?;
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        if let account = self.account {
            DBVCardStore.instance.vcard(for: account, completionHandler: { vcard in
                var dict: [String: String]? = nil;
                if let fn = vcard?.fn {
                    dict = ["name": fn];
                } else {
                    if let given = vcard?.givenName, !given.isEmpty {
                        if let surname = vcard?.surname, !surname.isEmpty {
                            dict = ["name": "\(given) \(surname)"];
                        } else {
                            dict = ["name": given];
                        }
                    } else if let surname = vcard?.surname, !surname.isEmpty {
                        dict = ["name": surname];
                    } else if let nick = vcard?.nicknames.first, !nick.isEmpty {
                        dict = ["name": nick];
                    }
                }
            
                DispatchQueue.main.async {
                    if let url = AppDelegate.XmppUri(jid: JID(account), action: nil, dict: dict).toURL()?.absoluteString, let qrCode = QRCode(string: url, scale: 10, foregroundColor: UIColor(named: "qrCodeForeground")!, backgroundColor: UIColor(named: "qrCodeBackground")!) {
                        if let img = UIImage(named: "tigaseLogo") {
                            let img2 = UIImage(cgImage: qrCode.cgImage);
                            let renderer = UIGraphicsImageRenderer(size: qrCode.size);
                            
                            let rect = CGRect(origin: .zero, size: qrCode.size);
                            self.qrCodeView.image = renderer.image(actions: { ctx in
                                img.draw(in: rect, blendMode: .normal, alpha: 1.0);
                                img2.draw(in: rect, blendMode: .normal, alpha: 1.0);
                            })
                        } else {
                            self.qrCodeView.image = UIImage(cgImage: qrCode.cgImage);
                        }
                    }
                }
            });
        }
    }
    
}

class QRCode {
    
    static func generateQRCode(_ string: String) -> CIImage? {
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil;
        }
        qrFilter.setValue(string.data(using: .ascii), forKey: "inputMessage");
        qrFilter.setValue("H", forKey: "inputCorrectionLevel");
        return qrFilter.outputImage;
    }
    
    static func getCodes(ciImage: CIImage) -> [[Bool]]? {
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            return nil;
        }
        let size = cgImage.width * cgImage.height * 4;
        var pixelData = [UInt8](repeating: 0, count: size);
        guard let cgContext = CGContext(
            data: &pixelData,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * cgImage.width,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil;
        }
        cgContext.draw(cgImage, in: ciImage.extent);
        return (0..<Int(cgImage.height)).map { y in
            (0..<Int(cgImage.width)).map { x in
                let offset = 4 * (x + y * Int(cgImage.width));
                return pixelData[offset + 0] == 0 && pixelData[offset + 1] == 0 && pixelData[offset + 2] == 0;
            }
        }
    }
    
    let size: CGSize;
    let cgImage: CGImage;
    
    init?(string: String, scale: Int, foregroundColor: UIColor, backgroundColor: UIColor) {
        guard let ciImage = QRCode.generateQRCode(string) else {
            return nil;
        }
        size = CGSize(width: Int(ciImage.extent.width) * scale, height: Int(ciImage.extent.height) * scale);
        
        guard let codes = QRCode.getCodes(ciImage: ciImage) else {
            return nil;
        }
        
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil;
        }
        context.setFillColor(backgroundColor.cgColor);
        let size = codes.count;
        let points = QRCode.getPoints(codeSize: size);
        for y in 0..<size {
            for x in 0..<size {
                if !codes[x][y] {
                    let isStatic = QRCode.isStatic(x: x, y: y, size: size, points: points);
                    let pointSize = isStatic ? CGFloat(scale) : (CGFloat(scale)/3);
                    let origin = isStatic ? CGPoint(x: CGFloat(y) * CGFloat(scale), y: CGFloat(size - x - 1) * CGFloat(scale)) : CGPoint(x: CGFloat(y) * CGFloat(scale) + pointSize, y: CGFloat(size - x - 1) * CGFloat(scale) + pointSize);
                    QRCode.drawPoint(context: context, rect: CGRect(origin: origin, size: CGSize(width: pointSize, height: pointSize)));
                }
            }
        }
        context.setFillColor(foregroundColor.cgColor);
        for y in 0..<size {
            for x in 0..<size {
                if codes[x][y] {
                    let isStatic = QRCode.isStatic(x: x, y: y, size: size, points: points);
                    let pointSize = isStatic ? CGFloat(scale) : (CGFloat(scale)/3);
                    let origin = isStatic ? CGPoint(x: CGFloat(y) * CGFloat(scale), y: CGFloat(size - x - 1) * CGFloat(scale)) : CGPoint(x: CGFloat(y) * CGFloat(scale) + pointSize, y: CGFloat(size - x - 1) * CGFloat(scale) + pointSize);
                    QRCode.drawPoint(context: context, rect: CGRect(origin: origin, size: CGSize(width: pointSize, height: pointSize)));
                }
            }
        }
        guard let cgImage = context.makeImage() else {
            return nil;
        }
        self.cgImage = cgImage;
    }
    
    static func getPoints(codeSize: Int) -> [Point] {
        let size = codeSize - 2;
        let version = ((size - 21) / 4) + 1;
        guard version != 1 else {
            return [];
        }
        let divs = 2 + version / 7;
        let total_dist = size - 7 - 6;
        let divisor = 2 * (divs - 1);
        
        let step = (total_dist + divisor / 2 + 1) / divisor * 2;
        let coords = [6] + (0...(divs-2)).map { size - 7 - (divs - 2 - $0) * step };
        
        var points = [Point]();
        for x in coords {
            for y in coords {
                let fx = x + 1;
                let fy = y + 1;
                if !((fx == 7 && fy == 7) || (fx == 7 && fy == (codeSize - 8)) || (fx == (codeSize - 8) && fy == 7)) {
                    points.append(Point(x: fx, y: fx));
                }
            }
        }
        return points;
    }
    
    static func drawPoint(context: CGContext, rect: CGRect) {
        context.fillEllipse(in: rect);
    }
    
    static func isStatic(x: Int, y: Int, size: Int, points: [Point]) -> Bool {
        if (x == 0 || y == 0 || x == (size-1) || y == (size-1)) {
            return true;
        }
        
        let xOnEdge = (x<=8) || (x>=size-9);
        let yOnEdge = (y<=8) || (y>=size-9);
        if (xOnEdge && yOnEdge && !(x>=size-9 && y>=size-9)) {
            return true;
        }
        
        if x==7 || y==7 {
            return true;
        }
        
        return points.contains(where: {
            x >= ($0.x - 2)
            && x <= ($0.x + 2)
                && y >= ($0.y - 2)
                && y <= ($0.y + 2);
        });
    }
    
    struct Point {
        let x: Int;
        let y: Int;
    }
}
