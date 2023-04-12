//
//  ChatEntryView.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 20/03/2023.
//  Copyright © 2023 Tigase, Inc. All rights reserved.
//

import MapKit
import SwiftUI
import Martin
import LinkPresentation

class CustomLinkView: LPLinkView {
//    override var intrinsicContentSize: CGSize {
//        CGSize(width: super.intrinsicContentSize.width,
//               height: super.intrinsicContentSize.height)
//    }
}

struct LinkViewRepresentable: UIViewRepresentable {
    
    typealias UIViewType = LPLinkView
    var metadata: LPLinkMetadata?
    var isUserInteractionEnabled: Bool = true
    
    init(url: URL) {
        self.metadata = LPLinkMetadata();
        self.metadata?.url = url;
    }

    init(metadata: LPLinkMetadata?, isUserInteractionEnabled: Bool = true) {
        self.metadata = metadata;
        self.isUserInteractionEnabled = isUserInteractionEnabled;
    }
        
    func makeUIView(context: Self.Context) -> LPLinkView {
        guard let metadata = metadata else { return CustomLinkView() }
        let linkView = LPLinkView(metadata: metadata)
        linkView.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
        linkView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        linkView.setContentHuggingPriority(.defaultHigh, for: .vertical);
        linkView.sizeToFit()
        linkView.isUserInteractionEnabled = isUserInteractionEnabled;
        return linkView
    }
    
    func updateUIView(_ uiView: LPLinkView, context: Self.Context) {
        
    }
    
}

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }

            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }

            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }

            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}


extension Text {
    
    struct Paragraph {
        let range: NSRange;
        let style: Style
    
        enum Style {
            case none
            case code
            case quote
        }
    }
    
    struct Section: Identifiable {
        let id: Int;
        let style: Paragraph.Style;
        let parts: [Part]
        
        func text() -> some View {
            var result = Text("");
            for part in parts {
                result = result + part.toText();
            }
            switch style {
            case .none:
                return AnyView(result.padding(0))
            case .quote:
                return AnyView(result.foregroundColor(Color(white: 0.2)).padding(.leading, 10).border(width: 2, edges: [.leading], color: Color.secondary))
            case .code:
                return AnyView(result.padding(.leading, 10).border(width: 2, edges: [.leading], color: Color.primary))
            }
        }
    }
    
    struct Part {
        let text: String;
        var color: Color?;
        var font: Font?;
        var underline: Bool = false;
        var link: URL?;
        
        func toText() -> Text {
            var result = Text(text);
            if let link = link {
                result = Text(.init(text))
            }
            if let color = color {
                result = result.foregroundColor(color);
            }
            if let font = font {
                result = result.font(font);
            }
            if underline {
                result = result.underline();
            }
            return result;
        }
    }
    
    struct Link {
        let range: NSRange;
        let url: URL;
    }
    
    static func from(markdown: String) -> some View {
//        if #available(iOS 15.0, *) {
//            return Text(try! AttributedString(markdown: markdown))
//        } else {
            let str = NSMutableAttributedString(string: markdown);
            Markdown.applyStyling(attributedString: str, defTextStyle: .body, showEmoticons: true);
        //var links: [Link] = [];
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
            let data = str.string;
            let matches = detector.matches(in: data, range: NSMakeRange(0, data.utf16.count));
            for match in matches {
                if let url = match.url, let scheme = url.scheme, ["https", "http"].contains(scheme) {
                    str.addAttribute(.link, value: url, range: match.range)
                }
                if let address = match.components {
                    let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                    let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                    str.addAttribute(.link, value: mapUrl, range: match.range)
                }
            }
        }
        var paragraphs: [Paragraph] = [];
        str.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: str.length), using: { value, range, _ in
            if let value = value as? NSParagraphStyle {
                if value === Markdown.codeParagraphStyle {
                    paragraphs.append(.init(range: range, style: .code))
                } else if value === Markdown.quoteParagraphStyle {
                    paragraphs.append(.init(range: range, style: .quote))
                } else {
                    paragraphs.append(.init(range: range, style: .none))
                }
            } else {
                paragraphs.append(.init(range: range, style: .none))
            }
        })
        
        var counter = 0;
        let sections = paragraphs.map({ paragraph in
            counter = counter + 1;
            var parts: [Part] = [];
            str.enumerateAttributes(in: paragraph.range, using: { attrs, range, _ in
                var text = str.attributedSubstring(from: range).string;
                var part = Part(text: text.hasSuffix("\n") && range.upperBound == paragraph.range.upperBound ? String(text.dropLast()) : text);
                if let color = attrs[.foregroundColor] as? UIColor {
                    part.color = Color(color)
                }
                if let font = attrs[.font] as? UIFont {
                    part.font = Font(font as CTFont)
                }
                if attrs[.underlineStyle] != nil {
                    part.underline = true;
                }
                if let link = attrs[.link] as? URL {
                    part.link = link
                }
                parts.append(part);
            })
            return Section(id: counter, style: paragraph.style, parts: parts);
        })
        
//        let texts = paragraphs.map({ paragraph in
//            var result = Text("");
//            str.enumerateAttributes(in: paragraph.range, using: { attrs, range, _ in
//                var text = Text(str.attributedSubstring(from: range).string);
//                if let color = attrs[.foregroundColor] as? UIColor {
//                    text = text.foregroundColor(Color(color))
//                }
//                if let font = attrs[.font] as? UIFont {
//                    text = text.font(Font(font as CTFont))
//                }
//                if attrs[.underlineStyle] != nil {
//                    text = text.underline()
//                }
////                    if let style = attrs[.paragraphStyle] as? NSParagraphStyle {
////                        if style === Markdown.codeParagraphStyle {
////                            text = text.foregroundColor(.secondary).fontWeight(.medium)
////                        } else if style === Markdown.quoteParagraphStyle {
////                            text = text.foregroundColor(.secondary).fontWeight(.medium)
////                        }
////                    }
//                result = result + text;
//            })
//            return result;
//        })
//
        return VStack(alignment: .leading) {
            ForEach(sections) { section in
//                var result = Text("");
//                for part in section.parts {
//
//                }
//                result
                section.text()
            }
        }
//        }
    }
    
}

struct AvatarViewNew: View {

    var nickname: String?;
    var avatar: Avatar
    var size: Double;
    @State var image: UIImage?;

    var body: some View {
        content.frame(width: size, height: size, alignment: .center).cornerRadius(size / 2).onReceive(avatar, perform: { image in self.image = image });
    }
    
    var content: some View {
        if let image = self.image {
            return AnyView(Image(uiImage: image).resizable())
        }
        else if let initials = nickname?.initials {
            return AnyView(Text(initials).font(.system(size: (size / 2)-2)).fontWeight(.bold).frame(width: size, height: size).foregroundColor(.white).background(LinearGradient(colors: [Color(white: 0.65), Color(white: 0.45)], startPoint: .top, endPoint: .bottom)))
        } else {
            return AnyView(Image(uiImage: AvatarManager.instance.defaultAvatar).resizable().imageScale(.small))
        }
    }
    
}

extension CLLocationCoordinate2D: Identifiable {
    public var id: String {
        "\(latitude)-\(longitude)"
    }
}

struct MapLocation: View {
    let location: CLLocationCoordinate2D
    
    var body: some View {
        Map(coordinateRegion: .constant(.init(center: location, span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5))), interactionModes: [], annotationItems: [location]) {
            MapPin(coordinate: $0)
        }.cornerRadius(10)
    }
}

import MobileCoreServices
import AVFoundation

struct AppendixView: View {
    
    let appendix: ChatAttachmentAppendix;
    let url: String;
    let item: ConversationEntry;
    var metadata: LPLinkMetadata?;
    var downloadedUrl: URL?;
//    @State var isPlaying: Bool = false;
    @StateObject private var audioHandler: AudioHandler = AudioHandler()
    
    init(item: ConversationEntry, appendix: ChatAttachmentAppendix, url: String) {
        self.appendix = appendix;
        print("appendix: \(appendix)")
        self.url = url;
        self.item = item;
        if let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            self.downloadedUrl = localUrl;
            metadata = MetadataCache.instance.metadata(for: "\(item.id)");
            if metadata == nil {
                MetadataCache.instance.generateMetadata(for: localUrl, withId: "\(item.id)", completionHandler: { newMeta in
                    if let meta = newMeta {
                        MetadataCache.instance.store(meta, for: "\(item.id)")
                        // need refresh!
                    }
                })
            } else {
                metadata?.originalURL = nil;
                metadata?.url = localUrl;
            }
        } else {
//            self.downloadedUrl = DownloadStore.instance.url(for: "\(item.id)");
        }
    }
    
    var body: some View {
        if !(appendix.mimetype?.starts(with: "audio/") ?? false), let metadata = metadata {
            LinkViewRepresentable(metadata: metadata, isUserInteractionEnabled: false).compositingGroup().contextMenu(menuItems: { self.contextMenu })
        } else {
            if appendix.state == .new {
                attachmentView.onAppear(perform: {
                    if DownloadStore.instance.url(for: "\(item.id)") == nil {
                        let sizeLimit = Settings.fileDownloadSizeLimit;
                        if sizeLimit > 0 {
//                            if (DBRosterStore.instance.item(for: item.conversation.account, jid: JID(item.conversation.jid))?.subscription ?? .none).isFrom || (DBChatStore.instance.conversation(for: item.conversation.account, with: item.conversation.jid) as? Room != nil) {
                                _ = DownloadManager.instance.download(item: item, url: url, maxSize: sizeLimit >= Int.max ? Int64.max : Int64(sizeLimit * 1024 * 1024));
//                                attachmentInfo.progress(show: true);
                                return;
                            }
//                        }
//                        attachmentInfo.progress(show: DownloadManager.instance.downloadInProgress(for: item));
                    }
                })
            } else {
                attachmentView
            }
//            let task = Task {
//                let provider = LPMetadataProvider();
//                guard let meta = try? await provider.startFetchingMetadata(for: URL(string: url)!) else { return; }
//                self.metadata = meta;
//            }
        }
    }
    
    var attachmentView: some View {
        HStack(alignment: .center) {
            filetypeIcon.resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 30, maxHeight: 30)
            VStack(alignment: .leading) {
                GeometryReader { geometry in
                    Text(filename).font(.caption).bold().truncationMode(.tail).lineLimit(2).frame(width: geometry.size.width, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(fileTypeName).font(.footnote)
                    Text(" - ").font(.footnote)
                    Text(fileSizeToString(appendix.filesize)).font(.footnote)
                    Spacer()
                }
            }
            Spacer()
            if let fileUrl = downloadedUrl {
                let _ = print("mimetype: \(appendix.mimetype)")
                if appendix.mimetype?.starts(with: "audio/") ?? false {
                    Button(action: {
                        if audioHandler.isPlaying {
                            audioHandler.stopPlayingAudio();
                        } else {
                            audioHandler.startPlayingAudio(fileUrl: fileUrl)
                        }
                    }, label: {
                        if audioHandler.isPlaying {
                            Image(systemName: "stop.circle").scaledToFill()
                        } else {
                            Image(systemName: "play.circle").scaledToFill()
                        }
                    })
                }
            } else if appendix.state == .downloaded {
                Menu(content: {
                    contextMenu
                }, label: {
                    Image(systemName: "ellipsis.circle")
                })
            } else {
                Button(action: {
                    _ = DownloadManager.instance.download(item: item, url: url, maxSize: Int64.max)
                }, label: {
                    Image(systemName: "arrow.down.circle").scaledToFill()
                })
            }
        }.padding(10).background(Color(UIColor.secondarySystemFill)).cornerRadius(10)
    }
    
    @ViewBuilder
    var contextMenu: some View {
            Button(action: {
                // FIX ME: we need to implement his
            }, label: {
                Label("Open", systemImage: "eye.fill")
            })
            Button(action: {
                UIPasteboard.general.strings = [url];
                UIPasteboard.general.string = url;
            }, label: {
                Label("Copy", systemImage: "doc.on.doc")
            })
            Button(action: {
                // FIX ME: we need to implement his
            }, label: {
                Label("Share", systemImage: "square.and.arrow.up")
            })
            Button(action: {
                DownloadStore.instance.deleteFile(for: "\(item.id)")
                DBChatHistoryStore.instance.updateItem(for: item.conversation, id: item.id, updateAppendix: { appendix in
                    appendix.state = .removed;
                })
            }, label: {
                Label("Delete", systemImage: "trash.circle")
            })
    }
    
    private class AudioHandler: NSObject, ObservableObject, AVAudioPlayerDelegate {
        @Published var isPlaying: Bool = false
        
        private var audioPlayer: AVAudioPlayer?;
        
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            audioPlayer?.stop();
            audioPlayer = nil;
            isPlaying = false;
        }
        
        func startPlayingAudio(fileUrl: URL) {
            stopPlayingAudio();
            do {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default);
                try? AVAudioSession.sharedInstance().setActive(true);
                audioPlayer = try AVAudioPlayer(contentsOf: fileUrl);
                audioPlayer?.delegate = self;
                audioPlayer?.volume = 1.0;
                audioPlayer?.play();
                isPlaying = true;
//                self.actionButton.setImage(UIImage(systemName: "pause.circle.fill")!, for: .normal);
            } catch {
                self.stopPlayingAudio();
            }
        }
        
        func stopPlayingAudio() {
            audioPlayer?.stop();
            audioPlayer = nil;
            isPlaying = false;
            //self.actionButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal);
        }
    }
    
    
    
//    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
//        audioPlayer?.stop();
//        audioPlayer = nil;
//        self.actionButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal);
//    }
//
//    @objc func actionTapped(_ sender: Any) {
//        if audioPlayer == nil {
//            self.startPlayingAudio();
//        } else {
//            self.stopPlayingAudio();
//        }
//    }
//}

    
    var filename: String {
        if let fileUrl = self.downloadedUrl {
            return fileUrl.lastPathComponent;
        } else {
            return appendix.filename ?? URL(string: url)?.lastPathComponent ?? "";
        }
    }
    
    var fileType: CFString? {
        if let fileUrl = self.downloadedUrl {
            return UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileUrl.pathExtension as CFString, nil)?.takeRetainedValue()
        } else if let mimetype = appendix.mimetype {
            return UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue();
        }
        return nil;
    }
    
    var fileTypeName: String {
        if let type = fileType, let typeName = UTTypeCopyDescription(type)?.takeRetainedValue() as String? {
            return typeName;
        }
        return "File";
    }
    
    var filetypeIcon: Image {
        if let type = fileType {
            if let img = UIImage.icon(forUTI: type as String) {
                return Image(uiImage: img);
            }
        }
        if let img = UIImage.icon(forUTI: "public.content") {
            return Image(uiImage: img);
        }
        return Image(systemName: "doc");
    }
    
    func fileSizeToString(_ sizeIn: Int?) -> String {
        guard let size = sizeIn else {
            return "Unknown";
        }
        let formatter = ByteCountFormatter();
        formatter.countStyle = .file;
        return formatter.string(fromByteCount: Int64(size));
    }
}

struct ConversationEntrySenderIdentifiable: Identifiable {
    let id = UUID();
    let sender: ConversationEntrySender;
}

struct ChatEntryView: View {
    
    var item: ConversationEntry;
    var metadata: LPLinkMetadata?;
    var isContinuation: Bool
    var needResize: (()->Void)?;
    
    init(item: ConversationEntry, isContinuation: Bool, needResize: (()->Void)? = nil) {
        self.item = item;
        self.isContinuation = isContinuation;
        self.needResize = needResize;
        self.metadata = MetadataCache.instance.metadata(for: "\(item.id)")
    }
    
    var body: some View {
        if item.payload == .unreadMessages {
            VStack(alignment: .center) {
                Text("Unread messages").font(.headline).foregroundColor(.secondary).padding(.top)
            }.frame(maxWidth: .infinity, alignment: .top)
        } else {
            HStack(alignment: . top) {
                if case let .marker(type, senders) = item.payload {
                    Spacer()
                    ForEach(senders.prefix(3).map({ ConversationEntrySenderIdentifiable(sender: $0) })) { sender in
                        AvatarViewNew(nickname: sender.sender.nickname, avatar: sender.sender.avatar(for: item.conversation), size: 16);
                    }
                    if senders.count > 3 {
                        Text("+\(senders.count-3)").font(.footnote).bold().foregroundColor(.secondary)
                    }
                    Text(type.label).font(.footnote).bold().foregroundColor(.secondary)
                } else if case let .message(message, _) = item.payload, message.starts(with: "/me ") {
                    Text((item.sender.nickname ?? "ME") + message.dropFirst(3)).font(.subheadline).italic().fontWeight(.bold).foregroundColor(.secondary).padding(.horizontal, 15)
                } else {
                    if isContinuation {
                        Image(uiImage: AvatarManager.instance.defaultAvatar).fixedSize().frame(width: 30, height: 0).hidden()
                    } else {
                        AvatarViewNew(nickname: item.sender.nickname, avatar: item.sender.avatar(for: item.conversation), size: 30)
                    }
                    VStack(alignment: .trailing) {
                        if !isContinuation {
                            HStack(alignment: .bottom) {
                                if let nickname = item.sender.nickname {
                                    Text(nickname).font(.headline).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(item.timestamp, style: .relative).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        switch item.payload {
                        case .message(let message, _):
                            HStack {
                                Text.from(markdown: message)
                                Spacer()
                            }
                            
                            //                    if let meta = metadata {
                            //    //                    HStack {
                            //    //                        Spacer()
                            //                            LinkViewRepresentable(metadata: meta).scaledToFit()
                            //    //                    }
                            //                    } else {
                            //                        LinkViewRepresentable(url: URL(string: "https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-advanced-text-styling-using-attributedstring")!).onAppear(perform: {
                            //                            let task = Task {
                            //                                let provider = LPMetadataProvider();
                            //                                guard let meta = try? await provider.startFetchingMetadata(for: URL(string: "https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-advanced-text-styling-using-attributedstring")!) else { return; }
                            //                                self.metadata = meta;
                            //                                self.needResize?();
                            //                            }
                            //                        }).scaledToFit()
                            //                    }
                        case .linkPreview(let url):
                            if let metadata = metadata {
                                LinkViewRepresentable(metadata: metadata)
                            } else {
                                LinkViewRepresentable(url: URL(string: url)!).onAppear(perform: {
                                    MetadataCache.instance.generateMetadata(for: URL(string: url)!, withId: "\(item.id)", completionHandler: { meta in
                                        guard meta != nil else {
                                            return;
                                        }
                                        //self.metadata = meta;
                                        DispatchQueue.main.async {
                                            self.needResize?();
                                        }
                                    })
                                })
                            }
                        case .retraction:
                            Text("Message retracted").foregroundColor(.secondary).italic()
                        case .location(let location):
                            MapLocation(location: location).frame(height: 300)
                        case .attachment(let url, let appendix):
                            AppendixView(item: item, appendix: appendix, url: url).scaledToFill()
                        default:
                            let _ = "1";
                        }
                    }
                }
            }.padding(.horizontal, 8).padding(.vertical, 2)//.fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ChatEntryView2: View {
    
    var item: ConversationEntry;
    @State var metadata: LPLinkMetadata?;
    var isContinuation: Bool
    
    var body: some View {
        VStack {
            if !isContinuation {
                HStack(alignment: .bottom) {
                    AvatarViewNew(nickname: item.sender.nickname, avatar: item.sender.avatar(for: item.conversation), size: 30).opacity(isContinuation ? 0.0 : 1.0)
                    if let nickname = item.sender.nickname {
                        Text(nickname).font(.headline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(item.timestamp, style: .relative).font(.system(size: 14)).foregroundColor(.secondary)
                }
            }
            switch item.payload {
            case .message(let message, _):
                //Text(.init(message)).font(.body)
                Text.from(markdown: message)
                if let meta = metadata {
                    HStack {
                        Spacer()
                        LinkViewRepresentable(metadata: meta)
                    }
                } else {
                    let task = Task {
                        let provider = LPMetadataProvider();
                        guard let meta = try? await provider.startFetchingMetadata(for: URL(string: "https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-advanced-text-styling-using-attributedstring")!) else { return; }
                        self.metadata = meta;
                    }
                }
            case .retraction:
                Text("Message retracted").foregroundColor(.secondary).italic()
            default:
                let _ = "1";
            }
        }.padding(.horizontal, 8)
    }
}

struct ChatEntryView_Previews: PreviewProvider {
    static var attachmentAppendix: ChatAttachmentAppendix = {
        var appendix = ChatAttachmentAppendix();
        appendix.filename = "dog-3277416_1280.jpg"
        appendix.mimetype = "image/jpeg"
        appendix.filesize = 4596;
        return appendix;
    }();
    
    static var previews: some View {
        ScrollView {
            VStack {
                ChatEntryView2(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .message(message: """
Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's **standard dummy** text ever since the *1500s*, when an _unknown_ printer took a galley of type and scrambled
```
var x = 100;
```
 it to make a type specimen book. It has survived not only five centuries, `but also the leap` into electronic typesetting, remaining essentially unchanged. https://onet.pl
>> Testing one more time if it works as expected or if something is wrong..
> It was popularised in the **1960s** with the release of *Letraset* sheets _containing_ Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.
""", correctionTimestamp: nil), options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: false)
                ChatEntryView2(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .message(message: "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. https://onet.pl It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.", correctionTimestamp: nil), options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: true)
                ChatEntryView2(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .retraction, options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: false)
                ChatEntryView(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .message(message: """
Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. https://onet.pl
>> It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.
""", correctionTimestamp: nil), options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: false)
                ChatEntryView(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .attachment(url: "https://cdn.pixabay.com/photo/2018/03/31/06/31/dog-3277416_1280.jpg", appendix: attachmentAppendix), options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: false)
                ChatEntryView(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .location(location: CLLocationCoordinate2D(latitude: 50.0646501, longitude: 19.9449799)), options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: false)
                ChatEntryView(item: .init(id: 1, conversation: ConversationKeyItem(account: BareJID("admin@localhost"), jid: BareJID("user@localhost")), timestamp: Date(), state: .incoming(.displayed), sender: .me(nickname: "Andrzej"), payload: .retraction, options: .init(recipient: .none, encryption: .none, isMarkable: true)), isContinuation: false)
            }
        }
    }
}
