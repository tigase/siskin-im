//
// Appearance.swift
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

class Appearance {
    
    static let CHANGED = Notification.Name("appearanceChanged");
    
    static let values: [Appearance] = [ ClassicAppearance(), OrioleLightAppearance(), PurpleLightAppearance(), ClassicDarkAppearance(), OrioleDarkAppearance(), PurpleDarkAppearance() ];
    
    fileprivate(set) static var current: Appearance! {
        didSet {
            if let delegate = UIApplication.shared.delegate, let w = delegate.window, let window = w {
            (window.rootViewController as? UISplitViewController)?.view.backgroundColor = current.systemBackground;
                (window.rootViewController as? UISplitViewController)?.viewControllers.forEach({ (controller) in
                    controller.view.backgroundColor = current.systemBackground;
                })
                window.backgroundColor = current.systemBackground;
            }
            UIButton.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = current.navigationBarTintColor;
            UISearchBar.appearance().tintColor = current.navigationBarTintColor;//current.tintColor();
//            UISearchBar.appearance().setScopeBarButtonTitleTextAttributes([NSAttributedString.Key.foregroundColor : Appearance.current.selectedSegmentedControlTextColor], for: .selected);
            UITabBar.appearance(whenContainedInInstancesOf: [UITabBarController.self]).tintColor = current.bottomBarTintColor;
            UITabBar.appearance(whenContainedInInstancesOf: [UITabBarController.self]).barTintColor = current.bottomBarBackgroundColor;
            NotificationCenter.default.post(name: Appearance.CHANGED, object: nil);
        }
    }
    
    static func sync() {
        let (colorType, subType) = settings();
        self.updateCurrent(colorType: colorType, subType: subType);
    }
    
    static func settings() -> (ColorType,SubColorType) {
        let val = Settings.AppearanceTheme.getString()!.split(separator: "-");
        let colorType = ColorType(rawValue: String(val[0]))!;
        let subType: SubColorType = val.count == 1 ? .auto : SubColorType(rawValue: String(val[1]))!;
        return (colorType, subType);
    }
    
//    @available(iOS 13.0, *)
//    static func update(from style: UIUserInterfaceStyle) {
//        switch style {
//        case .light, .dark:
//             let subtype: Appearance.SubColorType = style == .dark ? .dark : .light;
//            let colorType = Appearance.current.colorType;
//            Appearance.current = Appearance.values.first(where: { (item) -> Bool in
//                return item.colorType == colorType && item.subtype == subtype;
//            });
//        default:
//            break;
//        }
//    }
    
    static func updateCurrent(colorType: ColorType, subType: SubColorType) {
        var type = subType;
        if subType == .auto {
            if #available(iOS 13.0, *) {
                switch UITraitCollection.current.userInterfaceStyle {
                case .dark:
                    type = .dark;
                default:
                    type = .light;
                }
            } else {
                type = .light;
            }
        }
        Appearance.current = Appearance.values.first(where: { (app) -> Bool in
            return app.colorType == colorType && app.subtype == type;
        });
        
        let oldValue = Settings.AppearanceTheme.getString() ?? "";
        let newValue = "\(colorType.rawValue)-\(subType.rawValue)";
        if oldValue != newValue {
            Settings.AppearanceTheme.setValue(newValue);
        }
    }
    
    fileprivate static func set(appearance: Appearance) {
        Appearance.current = appearance;
    }
    
    fileprivate let baseColor: UIColor;
    let isBaseColorDark: Bool;
    let isDark: Bool;
    let id: String;
    let name: String;
    
    let navigationBarStyle: UIBarStyle;
    let navigationBarTintColor: UIColor;
    let navigationBarTextColor: UIColor;

    let tintColor: UIColor;
    let bottomBarTintColor: UIColor;
    let bottomBarBackgroundColor: UIColor;

    let controlBackgroundColor: UIColor;
    let selectedTextColor: UIColor;
    let selectedTextBackgroundColor: UIColor;
    let selectedSegmentedControlTextColor: UIColor;
    fileprivate var _incomingBubbleColor: UIColor;
    fileprivate var _outgoingBubbleColor: UIColor;
    
    let tableViewCellHighlightColor: UIColor;
    let tableViewHeaderFooterTextColor: UIColor;
    let textFieldBorderColor: UIColor;
    let placeholderColor: UIColor;

    let labelColor: UIColor;
    let secondaryLabelColor: UIColor;
    
    let systemBackground: UIColor;
    let secondarySystemBackground: UIColor;
    
    enum ColorType: String {
        case classic
        case oriole
        case purple
    }
    
    let colorType: ColorType;
    
    enum SubColorType: String {
        case light
        case dark
        case auto
        
        var label: String {
            return String(self.rawValue.prefix(1).uppercased()) + String(self.rawValue.dropFirst());
        }
        
        static let values: [SubColorType] = {
            if #available(iOS 13.0, *) {
                return [.auto, .light, .dark];
            } else {
                return [.light, .dark];
            }
        }();
    }
    
    let subtype: SubColorType;
    
    private static func baseColor(for type: ColorType, subtype: SubColorType) -> UIColor {
        switch type {
        case .classic:
            return subtype == .dark ? UIColor.black : UIColor.white;
        case .oriole:
            return subtype == .dark ? UIColor(named: "orioleColorDark")! : UIColor(named: "orioleColor")!;
        case .purple:
            return subtype == .dark ? UIColor(named: "purpleColorDark")! : UIColor(named: "purpleColor")!;
        }
    }
    
    private static func color(prefix: String, of type: ColorType, subtype: SubColorType) -> UIColor {
        let name = "\(type.rawValue)\(prefix)\(subtype == .dark ? "Dark" : "")";
        return UIColor(named: name)!;
    }

    private static func color(prefix: String, orPrefix: String, of type: ColorType, subtype: SubColorType) -> UIColor {
        let name = "\(type.rawValue)\(prefix)\(subtype == .dark ? "Dark" : "")";
        return UIColor(named: name) ?? color(prefix: orPrefix, of: type, subtype: subtype);
    }

    private static func color(prefix: String, subtype: SubColorType) -> UIColor {
        let name = "\(prefix)\(subtype == .dark ? "Dark" : "")";
        return UIColor(named: name)!;
    }

    init?(colorType: ColorType, subtype: SubColorType, id: String, name: String) {
        guard subtype != .auto else {
            return nil;
        }
        self.isDark = subtype == .dark;
        let baseColor: UIColor = Appearance.color(prefix: "Color", of: colorType, subtype: subtype);
        self.colorType = colorType;
        self.subtype = subtype;
        self.id = id;
        self.name = name;
        self.baseColor = baseColor;
        var brightness: CGFloat = 0;
        self.baseColor.getWhite(&brightness, alpha: nil);//.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil);
        self.isBaseColorDark = brightness < 0.4;
        print("name:", name, ", isBaseColorDark:", isBaseColorDark, ", isDark:", isDark, ", baseColor:", baseColor.toHex());
        
        self.tableViewCellHighlightColor = isDark ? UIColor(white: 1.0, alpha: 0.1) : UIColor(white: 0.0, alpha: 0.1);

        self.navigationBarTintColor = Appearance.color(prefix: "NavigationBarTintColor", of: colorType, subtype: subtype);
        if colorType != .classic {
            self.navigationBarTextColor = self.navigationBarTintColor;
            var navBrightness: CGFloat = 0;
            self.baseColor.getWhite(&navBrightness, alpha: nil);//.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil);
            self.navigationBarStyle = navBrightness < 0.5 ? UIBarStyle.black : UIBarStyle.default;
        } else {
            self.navigationBarTextColor = subtype == .dark ? UIColor.white : UIColor.black;
            self.navigationBarStyle = subtype == .dark ? UIBarStyle.black : UIBarStyle.default;
        }
        
        self.systemBackground = Appearance.color(prefix: "systemBackground", subtype: subtype);
        self.secondarySystemBackground = Appearance.color(prefix: "secondarySystemBackground", subtype: subtype);
        self.tintColor = Appearance.color(prefix: "TintColor", of: colorType, subtype: subtype);

        self.controlBackgroundColor = baseColor;
        self.labelColor = Appearance.color(prefix: "labelColor", subtype: subtype);
        self.secondaryLabelColor = Appearance.color(prefix: "secondaryLabelColor", subtype: subtype);
        
        self.bottomBarBackgroundColor = Appearance.color(prefix: "bottomTabBarBackgroundColor", subtype: subtype);
        self.bottomBarTintColor = Appearance.color(prefix: "BottomTabBarTintColor", orPrefix: "TintColor", of: colorType, subtype: subtype);
        
        
        self.selectedTextColor = isDark ? UIColor.black : UIColor.white;
        self.selectedTextBackgroundColor = baseColor.adjust(darker: isBaseColorDark, ratio: 0.3);
        
        
        self.selectedSegmentedControlTextColor = isBaseColorDark ? baseColor.adjust(brightness: 0.1) : baseColor.adjust(brightness: 1.0);
        self._incomingBubbleColor = isDark ? baseColor.adjust(brightness: 0.5) : baseColor.adjust(brightness: 0.8);
        self._outgoingBubbleColor = isDark ? baseColor.adjust(brightness: 0.3) : baseColor.adjust(brightness: 0.65);
        if colorType == .classic {
            self.tableViewHeaderFooterTextColor = isDark ? UIColor.lightGray : UIColor.darkGray;
        } else {
            self.tableViewHeaderFooterTextColor = Appearance.color(prefix: "BottomTabBarTintColor", orPrefix: "TintColor", of: colorType, subtype: subtype);
        }
        self.textFieldBorderColor = isDark ? UIColor.darkGray : UIColor.lightGray;
        self.placeholderColor = isDark ? UIColor.darkGray : UIColor.lightGray;
        
        print("navigationBarTextColor:", navigationBarTextColor.toHex());
        print("navigationBarTintColor:", navigationBarTintColor.toHex());
        print("bottomBarBackgroundColor:", bottomBarBackgroundColor.toHex());
        print("tintColor:", tintColor.toHex());
        print("bottomBarTintColor:", bottomBarTintColor.toHex());
//        print("textBackgroundColor:", textBackgroundColor.toHex());
        print("controlBackgroundColor:", controlBackgroundColor.toHex());
        print("selectedTextColor:", selectedTextColor.toHex());
        print("selectedTextBackgroundColor:", selectedTextBackgroundColor.toHex());
        print("selectedSegmentedControlTextColor:", selectedSegmentedControlTextColor.toHex());
        print("incomingBubbleColor:", incomingBubbleColor().toHex());
        print("outgoingBubbleColor:", outgoingBubbleColor().toHex());
        print("tableViewCellHighlightColor:", tableViewCellHighlightColor.toHex());
        print("tableViewHeaderFooterTextColor:", tableViewHeaderFooterTextColor.toHex());
        print("textFieldBorderColor:", textFieldBorderColor.toHex());
        print("placeholderColor:", placeholderColor.toHex());
    }
                
    func incomingBubbleColor() -> UIColor {
        return _incomingBubbleColor;
    }
    
    func outgoingBubbleColor() -> UIColor {
        return _outgoingBubbleColor;
    }
        
    func update(seachBar: UISearchBar) {
        seachBar.barStyle = self.navigationBarStyle;
        seachBar.tintColor = self.navigationBarTintColor;
        seachBar.barTintColor = self.controlBackgroundColor;
        seachBar.setNeedsLayout();
        seachBar.setNeedsDisplay();
//        seachBar.subviews.forEach { (subview1) in
//            subview1.subviews.forEach({ (subview2) in
//                if let textField = subview2 as? UITextField {
//                    if let backgroundView = textField.subviews.first {
////                        backgroundView.backgroundColor = Appearance.current.textBackgroundColor();
////                        backgroundView.layer.cornerRadius = 10;
////                        backgroundView.clipsToBounds = true;
//                    }
//                }
//            })
//        }
    }
}

class ClassicAppearance: Appearance {
    
    init() {
        let base = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0);
        super.init(colorType: .classic, subtype: .light, id: "classic", name: "Classic")!;
//        self._tableViewCellBackgroundColor = UIColor.white;
//        self._tableViewBackgroundColor = UIColor.white;
//        self._tableViewSeparatorColor = UIColor.lightGray;
        self._incomingBubbleColor = UIColor(red: 239/255, green: 239/255, blue: 244/255, alpha: 1.0);
        self._outgoingBubbleColor = base;
    }
    
}

class ClassicDarkAppearance: Appearance {
    
    init() {
        let blue = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0);
        super.init(colorType: .classic, subtype: .dark, id: "classic-dark", name: "Classic Dark")!;
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.65);
        self._outgoingBubbleColor = blue.adjust(brightness: 0.25);
    }
    
}

//class MonoDarkAppearance: Appearance {
//
//    init() {
//        let base = UIColor.black;
//        super.init(id: "mono-dark", name: "Black", isDark: true, baseColor: base);
//        self._tintColor = UIColor.white.adjust(brightness: 0.9);
//        self._navigationBarTintColor = UIColor.white.adjust(brightness: 0.9);
//        self._bottomBarBackgroundColor = base;
//        self._bottomBarTintColor = UIColor.white.adjust(brightness: 0.9);
//        self._secondaryTextColor = UIColor.white.adjust(brightness: 0.66);
//        self._tableViewBackgroundColor = baseColor.adjust(brightness: 0.05);
//        self._tableViewCellBackgroundColor = baseColor.adjust(brightness: 0.05);
//        self._tableViewHeaderFooterBackgroundColor = base.adjust(brightness: 0.10);
//        self._textBackgroundColor = self._tableViewCellBackgroundColor;
//        self._incomingBubbleColor = baseColor.adjust(brightness: 0.65);
//        self._outgoingBubbleColor = UIColor.white.adjust(brightness: 0.25);
//    }
//
//}


class OrioleLightAppearance: Appearance {
   
    init() {
        super.init(colorType: .oriole, subtype: .light, id: "oriole", name: "Oriole")!;
    }
}

class PurpleLightAppearance: Appearance {
    init() {
        super.init(colorType: .purple, subtype: .light, id: "purple", name: "Purple")!;
        
    }
}

class OrioleDarkAppearance: Appearance {
    
    init() {
        super.init(colorType: .oriole, subtype: .dark, id: "oriole-dark", name: "Oriole Dark")!;
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.6);
        self._outgoingBubbleColor = baseColor.adjust(brightness: 0.45);
    }
}

class PurpleDarkAppearance: Appearance {
    init() {
        let baseColor = UIColor(named: "purpleColor")!.adjust(brightness: 0.20);
        super.init(colorType: .purple, subtype: .dark, id: "purple-dark", name: "Purple Dark")!;
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.6);
        self._outgoingBubbleColor = baseColor.adjust(brightness: 0.45);
    }
}
