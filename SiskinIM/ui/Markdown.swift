//
// Markdown.swift
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

extension unichar: ExpressibleByUnicodeScalarLiteral {
    public typealias UnicodeScalarLiteralType = UnicodeScalar
    
    public init(unicodeScalarLiteral value: UnicodeScalar) {
        self.init(value.value);
    }
}

class Markdown {
    
    static let quoteParagraphStyle: NSParagraphStyle = {
        var paragraphStyle = NSMutableParagraphStyle();
        paragraphStyle.headIndent = 16;
        paragraphStyle.firstLineHeadIndent = 4;
        paragraphStyle.alignment = .natural;
        return paragraphStyle;
    }();
    
    static let codeParagraphStyle: NSParagraphStyle = {
        var paragraphStyle = NSMutableParagraphStyle();
        paragraphStyle.headIndent = 10;
        paragraphStyle.tailIndent = -10;
        paragraphStyle.firstLineHeadIndent = 10;
        paragraphStyle.alignment = .natural;
        return paragraphStyle;
    }();
    
    static func italic(font currentFont: UIFont) -> UIFont {
        var traits = currentFont.fontDescriptor.symbolicTraits;
        traits.insert(.traitItalic);
        traits.remove(.traitCondensed);
        return UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSymbolicTraits(traits)!, size: currentFont.fontDescriptor.pointSize);
    }
    
    static func bold(font currentFont: UIFont) -> UIFont {
        var traits = currentFont.fontDescriptor.symbolicTraits;
        traits.insert(.traitBold);
        traits.remove(.traitCondensed);
        print("curr:", currentFont);
        return UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSymbolicTraits(traits)!, size: currentFont.fontDescriptor.pointSize);
    }
    
    static func code(font currentFont: UIFont) -> UIFont {
        if #available(iOS 13.0, *) {
            return UIFont.monospacedSystemFont(ofSize: currentFont.fontDescriptor.pointSize, weight: .regular);
        } else {
            var traits = currentFont.fontDescriptor.symbolicTraits;
            traits.remove(.traitItalic);
            traits.remove(.traitBold);
            traits.remove(.traitCondensed);
            //        traits.insert(.traitMonoSpace);
            return UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSymbolicTraits(traits)!, size: currentFont.fontDescriptor.pointSize);
        }
    }
    
    static let NEW_LINE: unichar = "\n";
    static let GT_SIGN: unichar = ">";
    static let SPACE: unichar = " ";
    static let ASTERISK: unichar = "*";
    static let UNDERSCORE: unichar = "_";
    static let TILDE: unichar = "~";
    static let GRAVE_ACCENT: unichar = "`";
    static let CR_SIGN: unichar = "\r";
    
    static func applyStyling(attributedString msg: NSMutableAttributedString, font defFont: UIFont, showEmoticons: Bool) {
        let stylingColor = UIColor.init(white: 0.5, alpha: 1.0);
        
        var message = msg.string as NSString;
        
        var boldStart: Int? = nil;
        var italicStart: Int? = nil;
        var strikeStart: Int? = nil;
        var quoteStart: Int? = nil;
        var quoteLevel = 0;
        var idx = 0;
        
        var canStart = true;
        
        var wordIdx: Int? = showEmoticons ? 0 : nil;
        
        msg.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: msg.length));
        msg.addAttribute(.font, value: defFont, range: NSRange(location: 0, length: msg.length));
        
        while idx < message.length {
            let c = message.character(at: idx);
            if idx + 1 < message.length && message.character(at: idx + 1) == c {
                canStart = false;
            }
            switch c {
            case GT_SIGN:
                if quoteStart == nil && (idx == 0 || message.character(at: idx-1) == NEW_LINE) {
                    let start = idx;
                    while idx < message.length, message.character(at: idx) == GT_SIGN {
                        idx = idx + 1;
                    }
                    if idx < message.length && message.character(at: idx) == SPACE {
                        quoteStart = start;
                        quoteLevel = idx - start;
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: start, length: idx - start));
                    } else {
                        idx = idx - 1;
                    }
                }
            case ASTERISK:
                if boldStart == nil {
                    if canStart {
                        boldStart = idx + 1;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: boldStart! - 1, length: 1));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: 1));

                    msg.enumerateAttribute(.font, in: NSRange(location: boldStart!, length: idx - boldStart!), options: .init()) { (attr, range: NSRange, stop) -> Void in
                        let font = attr as? UIFont;
                        let boldFont = Markdown.bold(font: font ?? defFont);
                        msg.addAttribute(.font, value: boldFont, range: range);
                    }
                    
                    boldStart = nil;
                }
                canStart = true;
            case UNDERSCORE:
                if italicStart == nil {
                    if canStart {
                        italicStart = idx + 1;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: italicStart! - 1, length: 1));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: 1));

                    msg.enumerateAttribute(.font, in: NSRange(location: italicStart!, length: idx - italicStart!), options: .init()) { (attr, range: NSRange, stop) -> Void in
                        let font = attr as? UIFont;
                        let italicFont = Markdown.italic(font: font ?? defFont);
                        msg.addAttribute(.font, value: italicFont, range: range);
                    }

                    italicStart = nil;
                }
                canStart = true;
            case TILDE:
                if strikeStart == nil {
                    if canStart {
                        strikeStart = idx + 1;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: strikeStart! - 1, length: 1));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: 1));

                    msg.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: strikeStart!, length: idx - strikeStart!));

                    strikeStart = nil;
                }
                canStart = true;
            case GRAVE_ACCENT:
                if canStart {
                    let codeStart = idx;
                    wordIdx = nil;
                    while idx < message.length, message.character(at: idx) == "`" {
                        idx = idx + 1;
                    }
                    let codeCount = idx - codeStart;
                    print("code tag count = ", codeCount);
                    
                    var count = 0;
                    while idx < message.length {
                        if message.character(at: idx) == GRAVE_ACCENT {
                            count = count + 1;
                            if count == codeCount {
                                let tmp = idx + 1;
                                if tmp == message.length || [" ", "\n"].contains(message.character(at: tmp)) {
                                    break;
                                }
                            }
                        } else {
                            count = 0;
                        }
                        idx = idx + 1;
                    }
                    if codeCount != count {
                        idx = codeStart + codeCount;
                    } else {
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: codeStart, length: codeCount));
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: (idx+1)-codeCount, length: codeCount));

                        let codeFont = Markdown.code(font: defFont);
                        msg.addAttribute(.font, value: codeFont, range: NSRange(location: codeStart, length: idx - codeStart));

                        if idx == message.length {
                            wordIdx = message.length;
                        } else {
                            wordIdx = idx + 1;
                        }
                    }
                }
                canStart = true;
            case CR_SIGN, NEW_LINE, SPACE:
                if showEmoticons {
                    if wordIdx != nil && wordIdx! != idx {
                        // something is wrong, it looks like IDX points to replaced value!
                        let range = NSRange(location: wordIdx!, length: idx - wordIdx!);
                        if let emoji = String.emojis[message.substring(with: range)] {
                            let len = message.length;
                            print("replacing:", range, "for:", emoji, "in:", msg, "range:", NSRange(location: 0, length: msg.length));
                            msg.replaceCharacters(in: range, with: emoji);
                            message = msg.string as NSString;
                            let diff = message.length - len;
                            idx = idx + diff;
                        }
                    }
                    if idx < message.length {
                        wordIdx = idx + 1;
                    } else {
                        wordIdx = message.length;
                    }
                }
                if NEW_LINE == c {
                    boldStart = nil;
                    italicStart = nil;
                    strikeStart = nil;
                    if (quoteStart != nil) {
                        print("quote level:", quoteLevel);
                        if idx < message.length {
                            let range = NSRange(location: quoteStart!, length: idx - quoteStart!);
                            print("message possibly causing a crash:", message, "range:", range, "length:", message.length);
                            msg.addAttribute(.paragraphStyle, value: Markdown.quoteParagraphStyle, range: range);
                        }
                        quoteStart = nil;
                    }
                }
                canStart = true;
            default:
                canStart = false;
                break;
            }
            if idx < message.length {
                idx = idx + 1;
            }
        }

        if (quoteStart != nil) {
            msg.addAttribute(.paragraphStyle, value: Markdown.quoteParagraphStyle, range: NSRange(location: quoteStart!, length: idx - quoteStart!));
            quoteStart = nil;
        }

        if showEmoticons && wordIdx != nil && wordIdx! != idx {
            let range = NSRange(location: wordIdx!, length: idx - wordIdx!);
            if let emoji = String.emojis[message.substring(with: range)] {
                msg.replaceCharacters(in: range, with: emoji);
                message = msg.string as NSString;
            }
        }
        
        msg.fixAttributes(in: NSRange(location: 0, length: msg.length));
    }
    
}

extension String {
    
    static let emojisList = [
        "😳": ["O.o"],
        "☺️": [":-$", ":$"],
        "😄": [":-D", ":D", ":-d", ":d", ":->", ":>"],
        "😉": [";-)", ";)"],
        "😊": [":-)", ":)"],
        "😡": [":-@", ":@"],
        "😕": [":-S", ":S", ":-s", ":s", ":-/", ":/"],
        "😭": [";-(", ";("],
        "😮": [":-O", ":O", ":-o", ":o"],
        "😎": ["B-)", "B)"],
        "😐": [":-|", ":|"],
        "😛": [":-P", ":P", ":-p", ":p"],
        "😟": [":-(", ":("]
    ];
    
    static var emojis: [String:String] = Dictionary(uniqueKeysWithValues: String.emojisList.flatMap({ (arg0) -> [(String,String)] in
        let (k, list) = arg0
        return list.map { v in return (v, k)};
    }));
    
    func emojify() -> String {
        var result = self;
        let words = components(separatedBy: " ").filter({ s in !s.isEmpty});
        for word in words {
            if let emoji = String.emojis[word] {
                result = result.replacingOccurrences(of: word, with: emoji);
            }
        }
        return result;
    }
}
