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
    
    static let values: [Appearance] = [ ClassicAppearance(), OrioleLightAppearance(), PurpleLightAppearance(), ClassicDarkAppearance(), MonoDarkAppearance(), OrioleDarkAppearance(), PurpleDarkAppearance() ];
    
    static var current: Appearance! {
        didSet {
            if let delegate = UIApplication.shared.delegate, let w = delegate.window, let window = w {
            (window.rootViewController as? UISplitViewController)?.view.backgroundColor = current.tableViewBackgroundColor();
                (window.rootViewController as? UISplitViewController)?.viewControllers.forEach({ (controller) in
                    controller.view.backgroundColor = current.tableViewBackgroundColor();
                })
                window.backgroundColor = current.tableViewBackgroundColor();
            }
//            UINavigationBar.appearance().barStyle = current.navigationBarStyle();//current.isBaseColorDark ? .black : .default;
//            UINavigationBar.appearance().tintColor = current.navigationBarTintColor();
//            UINavigationBar.appearance().barTintColor = current.controlBackgroundColor();
            UIButton.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = current.navigationBarTintColor();
//            UIButton.appearance(whenContainedInInstancesOf: [BaseChatViewController.self]).tintColor = current.bottomBarTintColor();
            UISearchBar.appearance().tintColor = current.navigationBarTintColor();//current.tintColor();
            UISearchBar.appearance().setScopeBarButtonTitleTextAttributes([NSAttributedString.Key.foregroundColor : Appearance.current.selectedSegmentedControlTextColor()], for: .selected);
            //UIApplication.shared.delegate?.window??.tintColor = current.tintColor();
            UITabBar.appearance(whenContainedInInstancesOf: [UITabBarController.self]).tintColor = current.bottomBarTintColor();
            UITabBar.appearance(whenContainedInInstancesOf: [UITabBarController.self]).barTintColor = current.bottomBarBackgroundColor();
            //ChatBottomView.appearance().backgroundColor = current.bottomBarBackgroundColor();
            NotificationCenter.default.post(name: Appearance.CHANGED, object: nil);
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
    
    fileprivate var _navigationBarStyle: UIBarStyle;
    fileprivate var _navigationBarTintColor: UIColor;
    fileprivate var _tintColor: UIColor;
    fileprivate var _bottomBarTintColor: UIColor;
    fileprivate var _bottomBarBackgroundColor: UIColor;
    fileprivate var _textColor: UIColor;
    fileprivate var _secondaryTextColor: UIColor;
    fileprivate var _textBackgroundColor: UIColor;
    fileprivate var _controlBackgroundColor: UIColor;
    fileprivate var _selectedTextColor: UIColor;
    fileprivate var _selectedTextBackgroundColor: UIColor;
    fileprivate var _selectedSegmentedControlTextColor: UIColor;
    fileprivate var _labelColor: UIColor;
    fileprivate var _incomingBubbleColor: UIColor;
    fileprivate var _outgoingBubbleColor: UIColor;
    
    fileprivate var _tabBarTintColor: UIColor;
    fileprivate var _tableViewCellHighlightColor: UIColor;
    fileprivate var _tableViewCellBackgroundColor: UIColor;
    fileprivate var _tableViewSeparatorColor: UIColor;
    fileprivate var _tableViewBackgroundColor: UIColor;
    fileprivate var _tableViewHeaderFooterTextColor: UIColor;
    fileprivate var _tableViewHeaderFooterBackgroundColor: UIColor;
    fileprivate var _textFieldBorderColor: UIColor;
    fileprivate var _placeholderColor: UIColor;
    fileprivate var _navigationBarTextColor: UIColor;

    
    init(id: String, name: String, isDark: Bool, baseColor: UIColor) {
        self.id = id;
        self.name = name;
        self.baseColor = baseColor;
        var brightness: CGFloat = 0;
        self.baseColor.getWhite(&brightness, alpha: nil);//.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil);
        self.isBaseColorDark = brightness < 0.4;
        self.isDark = isDark;
        print("name:", name, ", isBaseColorDark:", isBaseColorDark, ", isDark:", isDark);
        
        self._tableViewCellHighlightColor = isDark ? UIColor(white: 1.0, alpha: 0.1) : UIColor(white: 0.0, alpha: 0.1);
        self._navigationBarStyle = brightness < 0.5 ? UIBarStyle.black : UIBarStyle.default;
        self._navigationBarTintColor = brightness < 0.5 ? UIColor.white : UIColor.black;
        self._navigationBarTextColor = _navigationBarTintColor;
        self._tintColor = baseColor.adjust(darker: !isBaseColorDark, ratio: 0.66);
        self._controlBackgroundColor = baseColor;
        self._textColor = isDark ? UIColor.white : UIColor.black;
        self._secondaryTextColor = _textColor.adjust(darker: isDark, ratio: 0.33);
        self._textBackgroundColor = isDark ? baseColor.adjust(brightness: 0.10) : UIColor.white;
        self._bottomBarBackgroundColor = self._textBackgroundColor;
        self._tableViewCellBackgroundColor = self._textBackgroundColor;
        self._bottomBarTintColor = isDark ? _tintColor : _controlBackgroundColor;
        self._selectedTextColor = isDark ? UIColor.black : UIColor.white;
        self._selectedTextBackgroundColor = baseColor.adjust(darker: isBaseColorDark, ratio: 0.3);
        self._selectedSegmentedControlTextColor = isBaseColorDark ? baseColor.adjust(brightness: 0.1) : baseColor.adjust(brightness: 1.0);
        self._labelColor = baseColor.adjust(darker: !isBaseColorDark, ratio: 0.66);
        self._incomingBubbleColor = isDark ? baseColor.adjust(brightness: 0.5) : baseColor.adjust(brightness: 0.8);
        self._outgoingBubbleColor = isDark ? baseColor.adjust(brightness: 0.3) : baseColor.adjust(brightness: 0.65);
        self._tabBarTintColor = isDark ? _tintColor : _controlBackgroundColor;
        self._tableViewSeparatorColor = isDark ? baseColor.adjust(brightness: 0.20) : baseColor.adjust(brightness: 0.90);
        self._tableViewBackgroundColor = isDark ? baseColor.adjust(brightness: 0.20) : baseColor.adjust(brightness: 0.95);
        self._tableViewHeaderFooterTextColor = baseColor.adjust(darker: !isDark, ratio: 0.5);
        self._tableViewHeaderFooterBackgroundColor = isDark ? baseColor.adjust(brightness: 0.15) : baseColor.adjust(brightness: 0.95);
        self._textFieldBorderColor = isDark ? UIColor.darkGray : UIColor.lightGray;
        self._placeholderColor = isDark ? UIColor.darkGray : UIColor.lightGray;
    }
    
    func navigationBarTextColor() -> UIColor {
        return _navigationBarTextColor;
    }
    
    func navigationBarStyle() -> UIBarStyle {
        return _navigationBarStyle;
    }
    
    func navigationBarTintColor() -> UIColor {
        return _navigationBarTintColor;
    }
    
    func bottomBarBackgroundColor() -> UIColor {
        return self._bottomBarBackgroundColor;
    }
    
    func tintColor() -> UIColor {
        return _tintColor;
    }
    
    func bottomBarTintColor() -> UIColor {
        return _bottomBarTintColor;
    }
    
    func textColor() -> UIColor {
        return _textColor;
    }
    func secondaryTextColor() -> UIColor {
        return _secondaryTextColor;
    }
    func textBackgroundColor() -> UIColor {
        return _textBackgroundColor;
    }
    func controlBackgroundColor() -> UIColor {
        return _controlBackgroundColor;
    }
    func selectedTextColor() -> UIColor {
        return _selectedTextColor;
    }
    func selectedTextBackgroundColor() -> UIColor {
        return _selectedTextBackgroundColor;
    }
    func selectedSegmentedControlTextColor() -> UIColor {
        return _selectedSegmentedControlTextColor;
    }
    func labelColor() -> UIColor {
        return _labelColor;
    }
    
    func incomingBubbleColor() -> UIColor {
        return _incomingBubbleColor;
    }
    
    func outgoingBubbleColor() -> UIColor {
        return _outgoingBubbleColor;
    }
    
    func tabBarTintColor() -> UIColor {
        return _tabBarTintColor;
    }
    
    func tableViewCellHighlightColor() -> UIColor {
        return _tableViewCellHighlightColor;
    }
    
    func tableViewCellBackgroundColor() -> UIColor {
        return _tableViewCellBackgroundColor;
    }
    
    func tableViewSeparatorColor() -> UIColor {
        return _tableViewSeparatorColor;
    }
    
    func tableViewBackgroundColor() -> UIColor {
        return _tableViewBackgroundColor;
    }
    
    func tableViewHeaderFooterTextColor() -> UIColor {
        return _tableViewHeaderFooterTextColor;
    }
    
    func tableViewHeaderFooterBackgroundColor() -> UIColor {
        return _tableViewHeaderFooterBackgroundColor;
    }
    
    func textFieldBorderColor() -> UIColor {
        return _textFieldBorderColor;
    }
    
    func placeholderColor() -> UIColor {
        return _placeholderColor;
    }
    
    func update(seachBar: UISearchBar) {
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
        super.init(id: "classic", name: "Classic", isDark: false, baseColor: UIColor.white);
        self._tintColor = base;
        self._navigationBarStyle = .default;
        self._navigationBarTintColor = base;
        self._tableViewCellBackgroundColor = UIColor.white;
        self._tableViewBackgroundColor = UIColor.white;
        self._tableViewSeparatorColor = UIColor.lightGray;
        self._tableViewHeaderFooterTextColor = UIColor.darkGray;
        self._bottomBarTintColor = base;
        self._incomingBubbleColor = UIColor(red: 239/255, green: 239/255, blue: 244/255, alpha: 1.0);
        self._outgoingBubbleColor = base;
    }
    
}

class ClassicDarkAppearance: Appearance {
    
    init() {
        let base = UIColor.black;
        let blue = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0);
        super.init(id: "classic-dark", name: "Classic Dark", isDark: true, baseColor: base);
        self._tintColor = blue;
        self._navigationBarTintColor = blue;
        self._bottomBarBackgroundColor = base;
        self._bottomBarTintColor = blue;
        self._secondaryTextColor = UIColor.white.adjust(brightness: 0.66);
        self._tableViewBackgroundColor = baseColor.adjust(brightness: 0.05);
        self._tableViewCellBackgroundColor = baseColor.adjust(brightness: 0.05);
        self._tableViewHeaderFooterBackgroundColor = base.adjust(brightness: 0.10);
        self._textBackgroundColor = self._tableViewCellBackgroundColor;
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.65);
        self._outgoingBubbleColor = blue.adjust(brightness: 0.25);
    }
    
}

class MonoDarkAppearance: Appearance {

    init() {
        let base = UIColor.black;
        super.init(id: "mono-dark", name: "Black", isDark: true, baseColor: base);
        self._tintColor = UIColor.white.adjust(brightness: 0.9);
        self._navigationBarTintColor = UIColor.white.adjust(brightness: 0.9);
        self._bottomBarBackgroundColor = base;
        self._bottomBarTintColor = UIColor.white.adjust(brightness: 0.9);
        self._secondaryTextColor = UIColor.white.adjust(brightness: 0.66);
        self._tableViewBackgroundColor = baseColor.adjust(brightness: 0.05);
        self._tableViewCellBackgroundColor = baseColor.adjust(brightness: 0.05);
        self._tableViewHeaderFooterBackgroundColor = base.adjust(brightness: 0.10);
        self._textBackgroundColor = self._tableViewCellBackgroundColor;
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.65);
        self._outgoingBubbleColor = UIColor.white.adjust(brightness: 0.25);
    }

}


class OrioleLightAppearance: Appearance {
   
    init() {
        super.init(id: "oriole", name: "Oriole", isDark: false, baseColor: UIColor(named: "orioleColor")!);
        self._tableViewBackgroundColor = UIColor.white;
    }
}

class PurpleLightAppearance: Appearance {
    init() {
        let baseColor = UIColor(named: "purpleColor")!.adjust(brightness: 0.45);
        super.init(id: "purple", name: "Purple", isDark: false, baseColor: baseColor);
        
        self._navigationBarStyle = .black;
        self._navigationBarTintColor = UIColor.white;
        self._tintColor = baseColor.adjust(brightness: 0.30);
        self._secondaryTextColor = UIColor.white.adjust(brightness: 0.33);
        self._tableViewBackgroundColor = UIColor.white;
    }
}

class OrioleDarkAppearance: Appearance {
    
    init() {
        let baseColor = UIColor(named: "orioleColor")!.adjust(brightness: 0.2);
        super.init(id: "oriole-dark", name: "Oriole Dark", isDark: true, baseColor: baseColor);
//        self._navigationBarTintColor = baseColor.adjust(brightness: 0.9);
        self._tableViewBackgroundColor = baseColor.adjust(brightness: 0.10);
        self._tableViewCellBackgroundColor = baseColor.adjust(brightness: 0.10);
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.6);
        self._outgoingBubbleColor = baseColor.adjust(brightness: 0.45);
    }
}

class PurpleDarkAppearance: Appearance {
    init() {
        let baseColor = UIColor(named: "purpleColor")!.adjust(brightness: 0.20);
        super.init(id: "purple-dark", name: "Purple Dark", isDark: true, baseColor: baseColor);
        self._navigationBarTintColor = baseColor.adjust(brightness: 0.85);
        self._secondaryTextColor = UIColor.white.adjust(brightness: 0.66);
        self._tableViewBackgroundColor = baseColor.adjust(brightness: 0.10);
        self._tableViewCellBackgroundColor = baseColor.adjust(brightness: 0.10);
        self._incomingBubbleColor = baseColor.adjust(brightness: 0.6);
        self._outgoingBubbleColor = baseColor.adjust(brightness: 0.45);
    }
}
