//
// MessageTextView.swift
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

//@IBDesignable
public class MessageTextView: UIView {
        
//    @IBInspectable public var fontSize: CGFloat = 14.0;
    
    private(set) var textView: UITextView!;
    
    var attributedText: NSAttributedString? {
        get {
            return textView.attributedText;
        }
        set {
            textView.attributedText = newValue;
        }
    }
    
    var text: String? {
        get {
            return textView.text;
        }
        set {
            textView.text = newValue;
        }
    }
    
//    @IBInspectable var textColor: UIColor = {
//        if #available(iOS 13.0, *) {
//            return UIColor.label;
//        } else {
//            return UIColor.black;
//        }
//    }();
    
    public override func awakeFromNib() {
        super.awakeFromNib();
        
        self.backgroundColor = UIColor.blue;
        let layoutManager = CustomLayoutManager();
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude));
        textContainer.widthTracksTextView = true;
        let textStorage = NSTextStorage();
        textStorage.addLayoutManager(layoutManager);
        layoutManager.addTextContainer(textContainer);
        //textContainer.replaceLayoutManager(layoutManager);
        self.textView = UITextView(frame: .zero, textContainer: textContainer);
        textView.translatesAutoresizingMaskIntoConstraints = false;
        textView.isScrollEnabled = false;
        textContainer.lineFragmentPadding = 1;
        self.textView.textContainerInset = .zero;
//        textContainer.widthTracksTextView = false;
        textContainer.heightTracksTextView = false;
        textView.isEditable = false;
        textView.isSelectable = true;
        textView.isUserInteractionEnabled = true;
        textView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline);
        textView.textColor = UIColor(named: "chatMessageText");
        textView.usesStandardTextScaling = false;
        self.addSubview(textView);
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            self.topAnchor.constraint(equalTo: textView.topAnchor),
            self.bottomAnchor.constraint(equalTo: textView.bottomAnchor)
        ])
    }
    
    class CustomLayoutManager: NSLayoutManager {
            
        override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin);
    //            let rect = self.boundingRect(forGlyphRange: glyphsToShow, in: self.textContainers.first!);
                
            let charRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil);
            textStorage!.enumerateAttribute(.paragraphStyle, in: charRange, options: [], using: { (value, range, pth) in
                guard let paragraph = value as? NSParagraphStyle else {
                    return;
                }
                if paragraph.tailIndent != 0 {
                    let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil);
                    let rect = self.boundingRect(forGlyphRange: glyphRange, in: self.textContainers.first!)
                    
                    UIColor.label.withAlphaComponent(0.5).setFill();
                    let path = UIBezierPath(rect: CGRect(origin: CGPoint(x: origin.x + rect.origin.x, y: origin.y + rect.origin.y), size: CGSize(width: 2, height: rect.height)));
                    path.fill();
                } else if paragraph.headIndent != 0 {
                    let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil);
                    let rect = self.boundingRect(forGlyphRange: glyphRange, in: self.textContainers.first!)
                        
                    UIColor.label.withAlphaComponent(0.2).setFill();
                    let path = UIBezierPath(rect: CGRect(x: (rect.origin.x > paragraph.firstLineHeadIndent) ? 1 + origin.x : rect.origin.x + origin.x, y: rect.origin.y + origin.y, width: 2, height: rect.height));
                    path.fill();
                }
            })
        }
        
    }
}
