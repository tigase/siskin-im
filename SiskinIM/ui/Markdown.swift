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
    
    static func applyStyling(attributedString msg: NSMutableAttributedString, font defFont: UIFont, showEmoticons: Bool) {
        let stylingColor = UIColor.init(white: 0.5, alpha: 1.0);
        
        var message = msg.string;
        
        var boldStart: String.Index? = nil;
        var italicStart: String.Index? = nil;
        var underlineStart: String.Index? = nil;
        //        var codeStart: String.Index? = nil;
        //        var codeCount: Int = 0;
        var quoteStart: String.Index? = nil;
        var quoteLevel = 0;
        var idx = message.startIndex;
        
        var canStart = true;
        
        var wordIdx: String.Index? = showEmoticons ? message.startIndex : nil;
        
        msg.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: msg.length));
        msg.addAttribute(.font, value: defFont, range: NSRange(location: 0, length: msg.length));
        
        while idx != message.endIndex {
            let c = message[idx];
            switch c {
            case ">":
                if quoteStart == nil && idx == message.startIndex || message[message.index(before: idx)] == "\n" {
                    let start = idx;
                    while idx != message.endIndex, message[idx] == ">" {
                        idx = message.index(after: idx);
                    }
                    if idx != message.endIndex && message[idx] == " " {
                        quoteStart = start;
                        quoteLevel = message.distance(from: start, to: idx)
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(start..<idx, in: message));
                    } else {
                        idx = message.index(before: idx);
                    }
                }
            case "*":
                let nidx = message.index(after: idx);
                if nidx != message.endIndex, message[nidx] == "*" {
                    if boldStart == nil {
                        if canStart {
                            boldStart = idx;
                        }
                    } else {
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(boldStart!...message.index(after: boldStart!), in: message));
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx...nidx, in: message));
                        
                        msg.enumerateAttribute(.font, in: NSRange(boldStart!...nidx, in: message), options: .init()) { (attr, range: NSRange, stop) -> Void in
                            let font = attr as? UIFont;
                            let boldFont = Markdown.bold(font: font ?? defFont);
                            msg.addAttribute(.font, value: boldFont, range: range);
                        }
                        
                        boldStart = nil;
                    }
                    canStart = true;
                    idx = nidx;
                } else {
                    if italicStart == nil {
                        if canStart {
                            italicStart = idx;
                        }
                    } else {
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(italicStart!...italicStart!, in: message));
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx...idx, in: message));
                        
                        msg.enumerateAttribute(.font, in: NSRange(italicStart!...idx, in: message), options: .init()) { (attr, range: NSRange, stop) -> Void in
                            let font = attr as? UIFont;
                            let italicFont = Markdown.italic(font: font ?? defFont);
                            msg.addAttribute(.font, value: italicFont, range: range);
                        }
                        italicStart = nil;
                    }
                    canStart = true;
                }
            case "_":
                if underlineStart == nil {
                    if canStart {
                        underlineStart = idx;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(underlineStart!...underlineStart!, in: message));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx...idx, in: message));
                    
                    msg.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(underlineStart!...idx, in: message));
                    underlineStart = nil;
                }
                canStart = true;
            case "`":
//                if codeStart == nil {
                if canStart {
                    let codeStart = idx;
                    let isBlock = message.startIndex == idx || (message[message.index(before: idx)] == "\n") || (message.distance(from: message.startIndex, to: idx) > 3 && message[message.index(idx, offsetBy: -1)] == " " && message[message.index(idx, offsetBy: -2)] == ">" && (message.startIndex == message.index(idx, offsetBy: -3) || message[message.index(idx, offsetBy: -3)] == "\n"));
                    wordIdx = nil;
                    while idx != message.endIndex, message[idx] == "`" {
                         idx = message.index(after: idx);
                     }
                     let codeCount = message.distance(from: codeStart, to: idx);
                     print("code tag count = ", codeCount);

                     var count = 0;
                     while idx != message.endIndex {
                         if message[idx] == "`" {
                             count = count + 1;
                             if count == codeCount {
                                 let tmp = message.index(after: idx);
                                 if tmp == message.endIndex || [" ", "\n"].contains(message[tmp]) {
                                     break;
                                 }
                             }
                         } else {
                             count = 0;
                         }
                         idx = message.index(after: idx);
                     }
                     if codeCount != count {
                         idx = message.index(before: idx);
                     } else {
                         msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(codeStart...message.index(codeStart, offsetBy: codeCount-1), in: message));
                         msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(message.index(idx, offsetBy: codeCount * -1)...idx, in: message));


                        let codeFont = Markdown.code(font: defFont);
                        msg.addAttribute(.font, value: codeFont, range: NSRange(codeStart...idx, in: message));
                    
                        if isBlock {
                            msg.addAttribute(.paragraphStyle, value: codeParagraphStyle, range: NSRange(codeStart...idx, in: message));
                        }

                        if message.distance(from: codeStart, to: idx) > 1 {
                            let clearRange = NSRange(message.index(codeStart, offsetBy: codeCount)...message.index(idx, offsetBy: codeCount * -1), in: message);
                            msg.removeAttribute(.underlineStyle, range: clearRange);
                            //msg.addAttribute(.foregroundColor, value: textColor ?? NSColor.textColor, range: clearRange);
                        }

                        if idx == message.endIndex {
                            wordIdx = message.endIndex;
                        } else {
                            wordIdx = message.index(after: idx);
                        }
                    }
                }
                canStart = true;
            case "\r", "\n", " ":
                if showEmoticons {
                    if wordIdx != nil && wordIdx! != idx {
                        // something is wrong, it looks like IDX points to replaced value!
                        if let emoji = String.emojis[String(message[wordIdx!..<idx])] {
                            msg.replaceCharacters(in: NSRange(wordIdx!..<idx, in: message), with: emoji);
                            let distance = message.distance(from: message.startIndex, to: wordIdx!);
                            message.replaceSubrange(wordIdx!..<idx, with: emoji);
                            // we are changing offset as length is changing!!
                            //                            idx = message.index(wordIdx!, offsetBy: emoji.lengthOfBytes(using: .utf8)-3);
                            idx = message.index(after: message.index(message.startIndex, offsetBy: distance));
                        }
                    }
                    if idx != message.endIndex {
                        wordIdx = message.index(after: idx);
                    } else {
                        wordIdx = message.endIndex;
                    }
                }
                if "\n" == c {
                    boldStart = nil;
                    underlineStart = nil;
                    italicStart = nil
                    if (quoteStart != nil) {
                        
                        msg.addAttribute(.paragraphStyle, value: Markdown.quoteParagraphStyle, range: NSRange(quoteStart!..<idx, in: message));
                        quoteStart = nil;
                    }
                }
                canStart = true;
            default:
                canStart = false;
                break;
            }
            if idx != message.endIndex {
                idx = message.index(after: idx);
            }
        }
        
        if (quoteStart != nil) {
            msg.addAttribute(.paragraphStyle, value: Markdown.quoteParagraphStyle, range: NSRange(quoteStart!..<idx, in: message));
            quoteStart = nil;
        }
        
        if showEmoticons && wordIdx != nil && wordIdx! != idx {
            if let emoji = String.emojis[String(message[wordIdx!..<idx])] {
                msg.replaceCharacters(in: NSRange(wordIdx!..<idx, in: message), with: emoji);
                message.replaceSubrange(wordIdx!..<idx, with: emoji);
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
