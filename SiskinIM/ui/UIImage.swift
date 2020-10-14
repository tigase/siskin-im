//
// UIImage.swift
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

extension UIImage {
    func scaled(maxWidthOrHeight: CGFloat, isOpaque: Bool = false) -> UIImage? {
        guard maxWidthOrHeight < size.height || maxWidthOrHeight < size.width else {
            return self;
        }
        let newSize = size.height > size.width ? CGSize(width: (size.width / size.height) * maxWidthOrHeight, height: maxWidthOrHeight) : CGSize(width: maxWidthOrHeight, height: (size.height / size.width) * maxWidthOrHeight);
        let format = imageRendererFormat;
        if isOpaque {
            format.opaque = isOpaque;
        }
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize));
        };
//        UIGraphicsBeginImageContextWithOptions(newSize, false, 0);
//        self.imageRendererFormat
//        self.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height));
//        defer {
//            UIGraphicsEndImageContext();
//        }
//        return  UIGraphicsGetImageFromCurrentImageContext();
    }
}
