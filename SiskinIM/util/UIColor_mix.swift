//
// UIColor_mix.swift
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

import UIKit

extension UIColor {
    func mix(color second: UIColor, ratio _ratio: CGFloat?) -> UIColor {
        var red1: CGFloat = 0;
        var green1: CGFloat = 0;
        var blue1: CGFloat = 0;
        var alpha1: CGFloat = 0;
        self.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1);
        var red2: CGFloat = 0;
        var green2: CGFloat = 0;
        var blue2: CGFloat = 0;
        var alpha2: CGFloat = 0;
        second.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2);
        
        let ratio = _ratio ?? alpha2;
        
        return UIColor(red: (1-ratio) * red1 + (ratio * red2), green: (1-ratio) * green1 + ratio * green2, blue: (1-ratio) * blue1 + ratio * blue2, alpha: 1.0);
    }
    
    func darker(ratio: CGFloat) -> UIColor {
        return adjust(darker: true, ratio: ratio);
    }
    
    func lighter(ratio: CGFloat) -> UIColor {
        return adjust(darker: false, ratio: ratio);
    }
    
    func adjust(darker: Bool, ratio: CGFloat) -> UIColor {
        var hue: CGFloat = 0;
        var saturation: CGFloat = 0;
        var brightness: CGFloat = 0;
        var alpha: CGFloat = 0;
        if !getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            var red1: CGFloat = 0;
            var green1: CGFloat = 0;
            var blue1: CGFloat = 0;
            var alpha1: CGFloat = 0;
            self.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1);
            let tmp = UIColor(red: red1, green: green1, blue: blue1, alpha: alpha1);
            if !tmp.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
                return self;
            }
        }
        
        let change =  ratio;//brightness * ratio;//darker ? (brightness * ratio) : ((1-brightness) * ratio);
        
        if darker {
            return UIColor(hue: hue, saturation: saturation, brightness: max(brightness - change, 0.0), alpha: alpha);
        } else {
            return UIColor(hue: hue, saturation: saturation, brightness: min(brightness + change, 1.0), alpha: alpha);
        }
    }
    
    func adjust1(brightness: CGFloat) -> UIColor {
        var hue: CGFloat = 0;
        var saturation: CGFloat = 0;
        var oldBrightness: CGFloat = 0;
        var alpha: CGFloat = 0;
        if !getHue(&hue, saturation: &saturation, brightness: &oldBrightness, alpha: &alpha) {
            var red1: CGFloat = 0;
            var green1: CGFloat = 0;
            var blue1: CGFloat = 0;
            var alpha1: CGFloat = 0;
            self.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1);
            let tmp = UIColor(red: red1, green: green1, blue: blue1, alpha: alpha1);
            if !tmp.getHue(&hue, saturation: &saturation, brightness: &oldBrightness, alpha: &alpha) {
                return self;
            }
        }
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha);
    }

    func adjust2(brightness: CGFloat) -> UIColor {
        var r: CGFloat = 0;
        var g: CGFloat = 0;
        var b: CGFloat = 0;
        var a: CGFloat = 0;
        self.getRed(&r, green: &g, blue: &b, alpha: &a);
        
        let minColor = min(r, g, b);
        let maxColor = max(r, g, b);
        
        let delta = maxColor - minColor;
        var hue: CGFloat = 0;
        if r == maxColor {
            hue = (g - b) / delta;
        } else if g == maxColor {
            hue = 2 + (b - r) / delta;
        } else {
            hue = 4 + (r - g) / delta;
        }
        
        hue = hue * 60;
        if hue < 0 {
            hue = hue + 360;
        }
        
        let saturation = maxColor == 0 ? 0 : (delta / maxColor);
        return UIColor(hue: hue/360, saturation: saturation, brightness: brightness, alpha: a);
    }
    
    func adjust(brightness: CGFloat) -> UIColor {
        var r: CGFloat = 0;
        var g: CGFloat = 0;
        var b: CGFloat = 0;
        var a: CGFloat = 0;
        self.getRed(&r, green: &g, blue: &b, alpha: &a);
        
        let minColor = min(r, g, b);
        let maxColor = max(r, g, b);
        
        var h: CGFloat = 0;
        var s: CGFloat = 0;
        var l = (maxColor + minColor) / 2;
        
        if minColor != maxColor {
            let d = maxColor - minColor;
            s = l > 0.5 ? (d / (2 - maxColor - minColor)) : (d / (maxColor + minColor));
            switch maxColor {
            case r:
                h = (g - b) / d + (g < b ? 6 : 0);
            case g:
                h = (b - r) / d + 2;
            case b:
                h = (r - g) / d + 4;
            default:
                break;
            }
            h = h / 6;
        }

        l = brightness;
        
        if s == 0 {
            r = l;
            g = l;
            b = l;
        } else {
            let fn = { (p: CGFloat, q: CGFloat, t1: CGFloat) -> CGFloat in
                var t = t1;
                if (t < 0) {
                    t = t + 1;
                }
                if (t > 1) {
                    t = t - 1;
                }
                if (t < 1/6) {
                    return p + (q - p) * 6 * t;
                }
                if (t < 1/2) {
                    return q;
                }
                if (t < 2/3) {
                    return p + (q - p) * (2/3 - t) * 6;
                }
                return p;
            };
            
            let q = l < 0.5 ? (l * (1 + s)) : ((l+s) - (l*s));
            let p = 2 * l - q;
            r = fn(p, q, h + 1/3);
            g = fn(p, q, h);
            b = fn(p, q, h - 1/3);
        }
        return UIColor(red: r, green: g, blue: b, alpha: a);
    }

    func toHex() -> String {
        guard let components = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .perceptual, options: nil)?.components, components.count >= 3 else {
            return "nil";
        }
        
        let r = lroundf(Float(components[0]) * 255);
        let g = lroundf(Float(components[1]) * 255);
        let b = lroundf(Float(components[2]) * 255);
        let a = components.count >= 4 ? lroundf(Float(components[3]) * 255) : 255;
        return String(format: "%02lX%02lX%02lX%02lX", r, g, b, a);
    }
}
